import Foundation
import AVFoundation
import MobileCoreServices

/// A custom delegate for AVAssetResourceLoader that enables on-the-fly caching.
class ResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    
    private let remoteUrl: URL
    var isTaskRunning = false
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var response: URLResponse?
    private var cacheFileHandle: FileHandle?
    private let cacheFilePath: String
    private let httpHeaders: [String: String]
    
    // Logging
    private let logger = CacheManager.shared.logger
    
    // Track loaded ranges
    private var loadingRequests = [AVAssetResourceLoadingRequest]()
    
    // State Tracking
    private var totalContentLength: Int64 = 0
    private var downloadedRanges = [Range<Int64>]()
    private let fileLock = NSLock() // Lock for file writing/reading and downloadedRanges
    
    // Read-Ahead Buffer
    private var readBuffer: Data?
    private var readBufferOffset: UInt64 = 0
    private let readBufferSize = 256 * 1024 // 256KB
    
    // State
    private var isHandled416 = false
    private var isDownloadComplete = false
    private var isCacheReady = false
    private var currentDownloadOffset: Int64 = 0
    private var maxContiguousOffset: Int64 = 0
    private var totalBytesReceivedInSession: Int64 = 0
    
    // Queue for thread safety
    private let queue = DispatchQueue(label: "com.native_cache_video_player.resourceLoader")
    
    // UTI caching
    private var cachedUTI: String?
    
    // Retry Logic
    private var maxRetries = 3
    private var retryCount = 0
    private var isRecoveringFrom416 = false
    
    // Cached Content Info
    private var cachedContentInfo: (type: String, length: Int64)?

    init(remoteUrl: URL, cacheFilePath: String, httpHeaders: [String: String] = [:]) {
        self.remoteUrl = remoteUrl
        self.cacheFilePath = cacheFilePath
        self.httpHeaders = httpHeaders
        super.init()
        
        // Initial integrity check
        _ = validateCacheIntegrity()
    }
    
    deinit {
        session?.invalidateAndCancel()
        cleanup()
    }
    
    // MARK: - Integrity & Cleanup
    
    private func validateCacheIntegrity() -> Bool {
        guard let metadata = CacheManager.shared.getMetadata(for: remoteUrl.absoluteString) else {
            return false
        }
        
        // Cache metadata in memory
        self.cachedContentInfo = (metadata.contentType, metadata.contentLength)
        self.totalContentLength = metadata.contentLength
        
        // Check file size consistency
        let currentSize = Int64(getCurrentFileSize())
        if currentSize > metadata.contentLength {
            logger.error("Cache corrupted: File size (\(currentSize)) > Metadata length (\(metadata.contentLength)). Resetting.")
            try? FileManager.default.removeItem(atPath: cacheFilePath)
            return false
        }
        
        // Check file header validity
        if currentSize >= 8 && !isCacheFileValid() {
            logger.error("Cache corrupted: Invalid MP4 header (no ftyp found). Resetting.")
            try? FileManager.default.removeItem(atPath: cacheFilePath)
            return false
        }
        
        return true
    }

    private func isCacheFileValid() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFilePath) else { return false }
        guard let handle = FileHandle(forReadingAtPath: cacheFilePath) else { return false }
        defer { try? handle.close() }
        
        let header: Data
        if #available(iOS 13.4, *) {
            guard let data = try? handle.read(upToCount: 8) else { return false }
            header = data
        } else {
            header = handle.readData(ofLength: 8)
        }
        
        guard header.count >= 8 else { return false }
        
        // MP4 files typically start with 'ftyp' (offset 4, 4 bytes)
        let ftypData = header.subdata(in: 4..<8)
        let ftyp = String(data: ftypData, encoding: .ascii)
        return ftyp == "ftyp"
    }
    
    private func cleanup() {
        cacheFileHandle?.closeFile()
        cacheFileHandle = nil
        isCacheReady = false
        readBuffer = nil
    }
    
    private func ensureCacheReady() -> Bool {
        if isCacheReady { return true }
        
        do {
            let directory = (cacheFilePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
            
            if !FileManager.default.fileExists(atPath: cacheFilePath) {
                FileManager.default.createFile(atPath: cacheFilePath, contents: nil, attributes: nil)
            }
            
            self.cacheFileHandle = FileHandle(forUpdatingAtPath: cacheFilePath)
            if self.cacheFileHandle == nil {
                logger.error("Failed to create file handle for \(cacheFilePath)")
                return false
            }
            isCacheReady = true
            return true
        } catch {
            logger.error("FileSystem Error: \(error)")
            return false
        }
    }
    
    // MARK: - Public Methods
    
    func cancel() {
        session?.invalidateAndCancel()
        queue.sync {
            cleanup()
        }
    }

    // MARK: - AVAssetResourceLoaderDelegate
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        queue.sync {
            if !ensureCacheReady() {
                let error = CacheError.fileSystemError(NSError(domain: "CreateHandle", code: -1, userInfo: nil))
                loadingRequest.finishLoading(with: error)
                return
            }
            loadingRequests.append(loadingRequest)
            processLoadingRequests()
            
            if !isTaskRunning && !isDownloadComplete {
                startDataRequest(offset: Int64(getCurrentFileSize()))
            }
        }
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.sync {
            if let index = loadingRequests.firstIndex(of: loadingRequest) {
                loadingRequests.remove(at: index)
            }
        }
    }
    
    // MARK: - Logic
    
    private func startDataRequest(offset: Int64 = -1, isRetry: Bool = false) {
        if isDownloadComplete { return }
        
        var targetOffset: Int64 = offset
        if targetOffset < 0 {
            targetOffset = findNextRequiredOffset()
        }
        
        if totalContentLength > 0 && targetOffset >= totalContentLength {
             logger.info("Download complete - reached EOF at \(targetOffset)")
            isDownloadComplete = true
            processLoadingRequests()
            return
        }
        
        // 1. Check if range is already downloaded
        if isRangeDownloaded(start: targetOffset) {
             targetOffset = findNextRequiredOffset()
             if targetOffset >= totalContentLength && totalContentLength > 0 {
                 isDownloadComplete = true
                 processLoadingRequests()
                 return
             }
        }
        
        currentDownloadOffset = targetOffset

        var request = URLRequest(url: remoteUrl)
        request.timeoutInterval = 60.0
        
        // Adaptive chunk size
        let endOffset = min(targetOffset + (5 * 1024 * 1024) - 1, (totalContentLength > 0 ? totalContentLength - 1 : Int64.max))
        let rangeHeader = "bytes=\(targetOffset)-\(endOffset)"
        request.addValue(rangeHeader, forHTTPHeaderField: "Range")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        session?.invalidateAndCancel()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 120
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
        isTaskRunning = true
        
        if !isRetry {
            totalBytesReceivedInSession = 0
        }
    }
    
    private func isRangeDownloaded(start: Int64) -> Bool {
        fileLock.lock()
        defer { fileLock.unlock() }
        for range in downloadedRanges {
            if range.contains(start) { return true }
        }
        return false
    }

    private func findNextRequiredOffset() -> Int64 {
        let currentSize = Int64(getCurrentFileSize())
        
        fileLock.lock()
        let ranges = downloadedRanges
        fileLock.unlock()

        for request in loadingRequests {
            if let dataRequest = request.dataRequest {
                let start = Int64(dataRequest.currentOffset)
                var isCached = false
                for range in ranges {
                    if range.contains(start) {
                        isCached = true
                        break
                    }
                }
                if !isCached {
                    return start
                }
            }
        }
        
        return currentSize
    }

    private func processLoadingRequests() {
        let currentFileSize = Int64(getCurrentFileSize())
        
        loadingRequests.removeAll { request in
            // 1. Content Information
            if let contentInfo = request.contentInformationRequest {
                if let info = self.cachedContentInfo {
                    contentInfo.contentType = info.type
                    contentInfo.contentLength = info.length
                    contentInfo.isByteRangeAccessSupported = true
                     if self.totalContentLength == 0 { self.totalContentLength = info.length }
                } 
                else if let metadata = CacheManager.shared.getMetadata(for: self.remoteUrl.absoluteString) {
                    self.cachedContentInfo = (metadata.contentType, metadata.contentLength)
                    contentInfo.contentType = metadata.contentType
                    contentInfo.contentLength = metadata.contentLength
                    contentInfo.isByteRangeAccessSupported = true
                    if self.totalContentLength == 0 { self.totalContentLength = metadata.contentLength }
                }
                else if let response = self.response as? HTTPURLResponse, (response.statusCode == 200 || response.statusCode == 206) {
                     let mimeType = response.mimeType ?? "video/mp4"
                     let uti = getUTI(for: mimeType, url: self.remoteUrl) ?? "public.mpeg-4"
                     let length = self.getTotalLength(response: response)
                     
                     self.cachedContentInfo = (uti, length)
                     CacheManager.shared.saveMetadata(for: self.remoteUrl.absoluteString, contentLength: length, contentType: uti)
                     
                     contentInfo.contentType = uti
                     contentInfo.contentLength = length
                     contentInfo.isByteRangeAccessSupported = true
                     if self.totalContentLength == 0 { self.totalContentLength = length }
                } else if currentFileSize > 0 {
                    return false
                } else {
                    return false
                }
            }
            
            // 2. Data Request
            if let dataRequest = request.dataRequest {
                let currentOffset = Int64(dataRequest.currentOffset)
                let requestedStart = Int64(dataRequest.requestedOffset)
                let lengthNeeded = Int64(dataRequest.requestedLength)
                let requestedEnd = requestedStart + lengthNeeded
                
                let availableEnd = min(requestedEnd, Int64(currentFileSize))
                let lengthToRead = Int(availableEnd - currentOffset)
                 
                 if lengthToRead > 0 {
                     if let data = readCachedData(offset: UInt64(currentOffset), length: lengthToRead) {
                         dataRequest.respond(with: data)
                         
                         let newCurrentOffset = currentOffset + Int64(data.count)
                         if newCurrentOffset >= requestedEnd {
                             request.finishLoading()
                             return true
                         }
                     }
                 }
                 
                 if self.isDownloadComplete && availableEnd == currentFileSize {
                     request.finishLoading()
                     return true
                 }
                 
                  if requestedStart >= currentFileSize {
                      if self.isDownloadComplete || self.isHandled416 {
                           request.finishLoading()
                           return true
                      }
                      
                      if !self.isTaskRunning && !self.isDownloadComplete {
                          self.startDataRequest(offset: requestedStart)
                      }
                  }
            } else {
                request.finishLoading()
                return true
            }
            
            return false
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.sync {
            self.response = response
            
            if let httpResponse = response as? HTTPURLResponse {
                if self.totalContentLength == 0 {
                    self.totalContentLength = getTotalLength(response: httpResponse)
                }
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 206 {
                    if !ensureCacheReady() {
                        completionHandler(.cancel)
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        do {
                            if #available(iOS 13.0, *) {
                                try cacheFileHandle?.truncate(atOffset: 0)
                            } else {
                                cacheFileHandle?.truncateFile(atOffset: 0)
                            }
                        } catch {
                            logger.error("Error truncating file: \(error)")
                        }
                    }
                } else if httpResponse.statusCode == 416 {
                    _ = ensureCacheReady()
                    let currentSize = Int64(getCurrentFileSize())
                    if totalContentLength > 0 && currentSize >= totalContentLength {
                        isDownloadComplete = true
                        isHandled416 = true
                        processLoadingRequests()
                        completionHandler(.cancel)
                        return
                    } else {
                        logger.warning("416 received at \(currentSize)/\(totalContentLength). Server may not support ranges. Re-starting from 0.")
                        
                        try? FileManager.default.removeItem(atPath: cacheFilePath)
                        downloadedRanges.removeAll()
                        
                        isRecoveringFrom416 = true
                        session.invalidateAndCancel()
                        isTaskRunning = false
                        startDataRequest(offset: 0, isRetry: true)
                        completionHandler(.cancel)
                        return
                    }
                } else if httpResponse.statusCode >= 400 {
                    handleError(CacheError.invalidResponse(httpResponse.statusCode))
                    completionHandler(.cancel)
                    return
                }
            }
            processLoadingRequests()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.sync {
            if let response = self.response as? HTTPURLResponse, response.statusCode >= 400 { return }
            if !ensureCacheReady() { return }
            
            fileLock.lock()
            defer { fileLock.unlock() }
            
            guard let handle = self.cacheFileHandle else { return }
            
            do {
                if #available(iOS 13.4, *) {
                    try handle.seek(toOffset: UInt64(self.currentDownloadOffset))
                    try handle.write(contentsOf: data)
                } else {
                    handle.seek(toFileOffset: UInt64(self.currentDownloadOffset))
                    handle.write(data)
                }
                
                if self.readBuffer != nil && self.readBufferOffset + UInt64(self.readBuffer!.count) == UInt64(self.currentDownloadOffset) {
                    if self.readBuffer!.count + data.count < self.readBufferSize * 2 {
                        self.readBuffer?.append(data)
                    } else {
                        self.readBuffer = nil 
                    }
                }
                
                let writeEnd = self.currentDownloadOffset + Int64(data.count)
                let newRange = self.currentDownloadOffset..<writeEnd
                appendAndMerge(range: newRange)
                
                if self.currentDownloadOffset <= self.maxContiguousOffset + 1 {
                    self.maxContiguousOffset = max(self.maxContiguousOffset, writeEnd)
                }
                
                self.currentDownloadOffset = writeEnd
                self.totalBytesReceivedInSession += Int64(data.count)
                
                if self.totalContentLength > 0 && self.currentDownloadOffset >= self.totalContentLength {
                    self.isDownloadComplete = true
                }
            } catch {
                logger.error("Write failed at \(self.currentDownloadOffset): \(error)")
                if let lastGoodOffset = downloadedRanges.last?.upperBound {
                    self.currentDownloadOffset = lastGoodOffset
                }
            }
            
            processLoadingRequests()
        }
    }
    
    private func appendAndMerge(range: Range<Int64>) {
        if let last = downloadedRanges.last {
            if last.upperBound >= range.lowerBound {
                let newLast = last.lowerBound..<max(last.upperBound, range.upperBound)
                downloadedRanges[downloadedRanges.count - 1] = newLast
            } else {
                downloadedRanges.append(range)
            }
        } else {
            downloadedRanges.append(range)
        }
        
        if downloadedRanges.count > 1 && downloadedRanges[downloadedRanges.count-2].upperBound >= downloadedRanges.last!.lowerBound {
            downloadedRanges.sort { $0.lowerBound < $1.lowerBound }
            var merged = [Range<Int64>]()
            var current = downloadedRanges[0]
            for r in downloadedRanges.dropFirst() {
                if r.lowerBound <= current.upperBound {
                    current = current.lowerBound..<max(current.upperBound, r.upperBound)
                } else {
                    merged.append(current)
                    current = r
                }
            }
            merged.append(current)
            downloadedRanges = merged
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.sync {
            isTaskRunning = false
            
            if let error = error {
                 let nsError = error as NSError
                  if nsError.code != NSURLErrorCancelled {
                       if retryCount < maxRetries && !isRecoveringFrom416 {
                           retryCount += 1
                           logger.info("Retrying network error: \(error.localizedDescription) (\(retryCount)/\(maxRetries))")
                           let delay = Double(retryCount) * 1.0
                           DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                               self.queue.async {
                                   self.startDataRequest(offset: self.currentDownloadOffset, isRetry: true)
                               }
                           }
                           return
                       }
                       handleError(CacheError.downloadFailed(error))
                  }
            } else {
                if !isDownloadComplete && totalContentLength > 0 && currentDownloadOffset < totalContentLength {
                    self.startDataRequest(offset: self.currentDownloadOffset, isRetry: false)
                }
            }
        }
    }
    
    private func handleError(_ error: Error) {
        for request in loadingRequests {
            request.finishLoading(with: error)
        }
        loadingRequests.removeAll()
        isDownloadComplete = true
        cleanup()
    }

    // MARK: - Helpers
    
    private func getCurrentFileSize() -> UInt64 {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: cacheFilePath)
            return attr[.size] as? UInt64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func readCachedData(offset: UInt64, length: Int) -> Data? {
        if cacheFileHandle == nil { return nil }
        
        if let buffer = readBuffer, 
           offset >= readBufferOffset, 
           offset + UInt64(length) <= readBufferOffset + UInt64(buffer.count) {
            let start = Int(offset - readBufferOffset)
            return buffer.subdata(in: start..<(start + length))
        }
        
        guard let handle = cacheFileHandle else { return nil }
        do {
            if #available(iOS 13.4, *) {
                try handle.seek(toOffset: offset)
            } else {
                handle.seek(toFileOffset: offset)
            }
            
            let lengthToRead = max(length, readBufferSize)
            let data = handle.readData(ofLength: lengthToRead)
            
            if data.count > 0 {
                readBuffer = data
                readBufferOffset = offset
                
                let returnLength = min(length, data.count)
                return data.subdata(in: 0..<returnLength)
            }
            return nil
        } catch {
            logger.error("Read failed: \(error)")
            return nil
        }
    }
    
    private func getTotalLength(response: HTTPURLResponse) -> Int64 {
        let headers = response.allHeaderFields
        // GCS Header
        let gcsLengthKey = headers.keys.first { ($0 as? String)?.localizedCaseInsensitiveContains("x-goog-stored-content-length") == true }
        if let key = gcsLengthKey {
            if let val = headers[key] as? String, let total = Int64(val) { return total }
            else if let val = headers[key] as? Int64 { return val }
            else if let val = headers[key] as? Int { return Int64(val) }
        }
        // Content-Range
        let contentRangeKey = headers.keys.first { ($0 as? String)?.localizedCaseInsensitiveContains("Content-Range") == true }
        if let key = contentRangeKey, let rangeHeader = headers[key] as? String {
             if let lastSlash = rangeHeader.lastIndex(of: "/") {
                 let totalStr = rangeHeader[rangeHeader.index(after: lastSlash)...]
                 if let total = Int64(totalStr) { return total }
             }
        }
        if response.statusCode == 200 { return response.expectedContentLength }
        return 0
    }
    
    private func getUTI(for mimeType: String, url: URL? = nil) -> String? {
        if let cached = cachedUTI { return cached }
        var uti: String?
        if mimeType.contains("octet-stream") || mimeType.isEmpty {
            if let ext = url?.pathExtension, !ext.isEmpty {
                if let unmanagedUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil) {
                    uti = unmanagedUTI.takeRetainedValue() as String
                }
            }
        }
        if uti == nil && !mimeType.isEmpty {
            if let unmanagedUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil) {
                uti = unmanagedUTI.takeRetainedValue() as String
            }
        }
        if uti == nil {
            if mimeType.contains("mp4") { uti = "public.mpeg-4" }
            else if mimeType.contains("video/") { uti = "public.movie" }
        }
        cachedUTI = uti
        return uti
    }
}
