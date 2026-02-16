import Foundation
import CommonCrypto
#if canImport(Flutter)
import Flutter
#endif

/// Manages the local video cache on iOS.
///
/// This singleton class provides unified access to the cache directory and handles
/// file system operations.
class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectoryName = "native_cache_video_player"
    let logger: Logger = DefaultLogger()
    
    // Configuration
    private var maxCacheSize: Int64 = 500 * 1024 * 1024
    
    // Serial queue for file system safety
    private let cacheQueue = DispatchQueue(label: "com.native_cache_video_player.cacheQueue")
    
    private var cacheDirectory: URL {
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(cacheDirectoryName)
    }
    
    init() {
        createCacheDirectory()
        setupMemoryObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupMemoryObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        logger.warning("CacheManager: Received system memory warning. Local cache is safe, but plugin will purge idle players.")
    }
    
    private func createCacheDirectory() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Returns the local file system path for a cached video based on its URL.
    func getCachePath(for url: String) -> String {
        let fileName = sha256(url) + ".mp4"
        return cacheDirectory.appendingPathComponent(fileName).path
    }
    
    private func getMetadataPath(for url: String) -> String {
        let fileName = sha256(url) + ".meta"
        return cacheDirectory.appendingPathComponent(fileName).path
    }
    
    func saveMetadata(for url: String, contentLength: Int64, contentType: String) {
        let path = getMetadataPath(for: url)
        let metadata: [String: Any] = [
            "contentLength": contentLength,
            "contentType": contentType,
            "url": url,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            try? jsonString.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    
    func getMetadata(for url: String) -> (contentLength: Int64, contentType: String)? {
        let path = getMetadataPath(for: url)
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let contentLength = json["contentLength"] as? Int64,
              let contentType = json["contentType"] as? String else {
            return nil
        }
        return (contentLength, contentType)
    }
    
    func updateConfig(maxSize: Int64, concurrent: Int, concurrentWhilePlaying: Int) {
        cacheQueue.async {
            if maxSize <= 0 {
                self.logger.error("Invalid max cache size: \(maxSize)")
                return
            }
            self.maxCacheSize = maxSize
        }
    }
    
    // MARK: - File System Operations
    
    func clearAllCache(completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        cacheQueue.async {
            do {
                let fileURLs = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil, options: [])
                if fileURLs.isEmpty {
                    completion(false, nil)
                    return
                }
                for fileURL in fileURLs {
                    try self.fileManager.removeItem(at: fileURL)
                }
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }
    
    func removeFile(for url: String, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        cacheQueue.async {
            let path = self.getCachePath(for: url)
            if self.fileManager.fileExists(atPath: path) {
                do {
                    try self.fileManager.removeItem(atPath: path)
                    completion(true, nil)
                } catch {
                    completion(false, error)
                }
            } else {
                completion(false, nil)
            }
        }
    }
    
    func enforceCacheLimit(maxSize: Int64, completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        cacheQueue.async {
            do {
                let fileURLs = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [])
                
                var totalSize: Int64 = 0
                var files = [(url: URL, size: Int64, date: Date)]()
                
                for fileURL in fileURLs {
                    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    if let size = values.fileSize, let date = values.contentModificationDate {
                        let sizeInt64 = Int64(size)
                        totalSize += sizeInt64
                        files.append((url: fileURL, size: sizeInt64, date: date))
                    }
                }
                
                if totalSize <= maxSize {
                    completion(false, nil)
                    return
                }
                
                files.sort { $0.date < $1.date }
                
                var deletedAny = false
                for file in files {
                    if totalSize <= maxSize { break }
                    
                    try self.fileManager.removeItem(at: file.url)
                    totalSize -= file.size
                    deletedAny = true
                }
                completion(deletedAny, nil)
            } catch {
                completion(false, error)
            }
        }
    }
    
    private func sha256(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
