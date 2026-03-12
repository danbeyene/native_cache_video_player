import Flutter
import AVFoundation
import CommonCrypto

/// A Flutter texture wrapper around AVPlayer that supports native caching.
///
/// This class manages the lifecycle of the AVPlayer, registers as a Flutter texture,
/// and integrates with [ResourceLoaderDelegate] to handle cached playback.
class FLTVideoPlayer: NSObject, FlutterTexture {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var resourceLoaderDelegate: ResourceLoaderDelegate?
    private let registrar: FlutterPluginRegistrar
    private var eventChannel: FlutterEventChannel?
    private var _eventSink: FlutterEventSink?
    private let dataSource: String
    
    var textureId: Int64 = -1
    private var isLooping = false
    private var isInitialized = false
    private var captionOffset: Int = 0
    
    private var httpHeaders = [String: String]()
    private var remoteUrl: URL? // Normalized URL for cache operations
    
    // Retry Logic
    private var playerRetryCount = 0
    private let maxPlayerRetries = 3
    
    init(uri: String, registrar: FlutterPluginRegistrar, httpHeaders: [String: String] = [:]) {
        self.registrar = registrar
        self.httpHeaders = httpHeaders
        self.dataSource = uri
        super.init()
        setupPlayer(uri: uri)
    }
    
    /// Configures the event channel for streaming player state and buffering updates to Flutter.
    func setupEventChannel(textureId: Int64) {
        self.textureId = textureId
        let channel = FlutterEventChannel(name: "native_cache_video_player/videoEvents\(textureId)", binaryMessenger: registrar.messenger())
        channel.setStreamHandler(self)
        self.eventChannel = channel
    }
    
    private func setupPlayer(uri: String) {
        guard let url = URL(string: uri) else { return }
        
        let asset: AVURLAsset
        if url.scheme == "cache" {
            // Custom scheme! Use ResourceLoader
            asset = AVURLAsset(url: url)
            
            // Reconstruct the actual remote URL (replace cache:// with https://)
            var remoteComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            remoteComponents.scheme = "https"
            self.remoteUrl = remoteComponents.url!
            
            let remoteUrlString = self.remoteUrl!.absoluteString
            let cachePath = CacheManager.shared.getCachePath(for: remoteUrlString)
            
            resourceLoaderDelegate = ResourceLoaderDelegate(remoteUrl: self.remoteUrl!, cacheFilePath: cachePath, httpHeaders: httpHeaders)
            
            let queue = DispatchQueue(label: "com.native_cache_video_player.resourceLoaderQueue")
            asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: queue)
        } else {
            // Standard URL
            asset = AVURLAsset(url: url)
            self.remoteUrl = url
        }
        
        playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["duration", "tracks", "preferredTransform"])
        
        if #available(iOS 10.0, *) {
            playerItem?.preferredForwardBufferDuration = 3.0
            player?.automaticallyWaitsToMinimizeStalling = true
        }
        
        player = AVPlayer(playerItem: playerItem)
        
        if #available(iOS 10.0, *) {
            player?.automaticallyWaitsToMinimizeStalling = true
        }
        
        player?.addObserver(self, forKeyPath: "rate", options: .new, context: nil)
        
        setupVideoOutput()
        addObservers(item: playerItem!)
        setupDisplayLink()
    }
    
    private func setupVideoOutput() {
        let pixBuffAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixBuffAttributes)
        playerItem?.add(videoOutput!)
    }
    
    private func addObservers(item: AVPlayerItem) {
        item.addObserver(self, forKeyPath: "status", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "presentationSize", options: .new, context: nil)
        item.addObserver(self, forKeyPath: "duration", options: .new, context: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: item)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }
        
        switch keyPath {
        case "status":
            if let item = playerItem {
                if item.status == .readyToPlay {
                    if !isInitialized {
                        isInitialized = true
                        sendInitialized()
                    }
                } else if item.status == .failed {
                    let error = item.error
                    let errorDescription = error?.localizedDescription ?? "Unknown error"
                    let nsError = error as NSError?
                    
                    print("NCVP: Player [ERROR] Item failed: \(errorDescription) (Code: \(nsError?.code ?? 0)) (URL: \(dataSource))")
                    
                    // Don't retry on certain errors
                    let unrecoverableErrors = [-1001, -1003, -1009, -11849] // Timeout, DNS, offline, operation stopped
                    if let code = nsError?.code, unrecoverableErrors.contains(code) {
                        if code == -11849 { // Operation stopped (416 case)
                            print("NCVP: Player [416] Restarting from beginning")
                            disposePlayerOnly()
                            setupPlayer(uri: dataSource)
                            return
                        }
                    }
                    
                    if playerRetryCount < maxPlayerRetries {
                        playerRetryCount += 1
                        print("NCVP: Player [RETRY] Re-initializing player (Attempt \(playerRetryCount)/\(maxPlayerRetries)) for \(dataSource)...")
                        
                        // Safe Retry: Only delete cache if it's NOT a network timeout or reachability issue.
                        let networkErrorCodes = [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet]
                        
                        let shouldDeleteCache = !networkErrorCodes.contains(nsError?.code ?? 0)
                        
                        if shouldDeleteCache {
                            if let urlString = self.remoteUrl?.absoluteString {
                                CacheManager.shared.removeFile(for: urlString) { success, _ in
                                    if success {
                                        print("NCVP: Player [CLEANUP] Deleted suspected corrupt cache file for retry: \(urlString)")
                                    }
                                }
                            }
                        } else {
                            print("NCVP: Player [RESUME] Preserving partial cache for network retry (Code: \(nsError?.code ?? 0))")
                        }
                        
                        // Exponential backoff
                        let delay = Double(playerRetryCount) * 1.5
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.disposePlayerOnly()
                            self?.setupPlayer(uri: self?.dataSource ?? "")
                        }
                    } else {
                        print("NCVP: Player [FAILURE] Max retries reached. Reporting error to Flutter.")
                        _eventSink?(FlutterError(code: "VideoError", 
                                                 message: "Failed to load video after \(maxPlayerRetries) retries: \(errorDescription)", 
                                                 details: dataSource))
                    }
                }
            }
        case "loadedTimeRanges":
            // Send buffering update
            if let ranges = playerItem?.loadedTimeRanges, let first = ranges.first {
                let range = first.timeRangeValue
                let start = CMTimeGetSeconds(range.start)
                let duration = CMTimeGetSeconds(range.duration)
                var values: [String: Any] = [:]
                values["event"] = "bufferingUpdate"
                values["values"] = [[Int(start * 1000), Int((start + duration) * 1000)]]
                _eventSink?(values)
            }
        case "presentationSize":
            if isInitialized { 
                // Handle size change if needed
            }
        case "duration":
            break
        case "rate":
            break
        default:
            break
        }
    }
    
    /// Signals to the Flutter layer that the player has finished initialization 
    /// and provides metadata like duration and video dimensions.
    private func sendInitialized() {
        guard let item = playerItem, isInitialized else { return }
        let size = item.presentationSize
        var width = size.width
        var height = size.height
        let duration = Int(CMTimeGetSeconds(item.duration) * 1000)
        
        var event: [String: Any] = [:]
        event["event"] = "initialized"
        event["duration"] = duration
        event["width"] = width
        event["height"] = height
        _eventSink?(event)
        
        // Optimization: Manually trigger a frame update so the first frame is visible immediately.
        registrar.textures().textureFrameAvailable(textureId)
    }
    
    @objc func itemDidPlayToEndTime() {
        if isLooping {
            seek(to: 0)
            play()
        } else {
            _eventSink?(["event": "completed"])
        }
    }
    
    private var displayLink: CADisplayLink?
    
    /// MARK: - FlutterTexture
    
    /// Provides the latest video frame to the Flutter engine as a pixel buffer.
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let output = videoOutput, let item = playerItem else { return nil }
        let time = item.currentTime()
        
        if output.hasNewPixelBuffer(forItemTime: time) {
            if let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                return Unmanaged.passRetained(buffer)
            }
        }
        return nil
    }

    func onTextureUnregistered(_ texture: FlutterTexture) {
        // Texture unregistered
    }
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.isPaused = true
    }
    
    @objc func onDisplayLink(_ link: CADisplayLink) {
        guard let output = videoOutput, let item = playerItem else { return }
        
        let time = item.currentTime()
        if output.hasNewPixelBuffer(forItemTime: time) {
            registrar.textures().textureFrameAvailable(textureId)
        }
    }
    
    // MARK: - Method Handling
    
    func handle(_ call: FlutterMethodCall, result: @escaping (Any?) -> Void) {
        switch call.method {
        case "play": play(); result(nil)
        case "pause": pause(); result(nil)
        case "setLooping":
            if let args = call.arguments as? [String: Any], let looping = args["looping"] as? Bool {
                setLooping(looping)
            }
            result(nil)
        case "setVolume":
             if let args = call.arguments as? [String: Any], let volume = args["volume"] as? Double {
                setVolume(volume)
            }
            result(nil)
        case "setCaptionOffset":
            if let args = call.arguments as? [String: Any], let offset = args["offset"] as? Int {
                setCaptionOffset(offset)
            }
            result(nil)
        case "seekTo":
            if let args = call.arguments as? [String: Any], let position = args["position"] as? Int {
                seek(to: position)
            }
            result(nil)
        case "setPlaybackSpeed":
             if let args = call.arguments as? [String: Any], let speed = args["speed"] as? Double {
                setPlaybackSpeed(speed)
            }
            result(nil)
        case "position":
            result(getPosition())
        case "dispose":
            dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Controls Implementation
    
    func isPlaying() -> Bool {
        return player?.rate != 0 && player?.error == nil
    }

    func play() {
        applyAudioSessionCategory()
        if #available(iOS 10.0, *) {
            // Cap buffering to 5 seconds to prevent heap bloat while playing
            playerItem?.preferredForwardBufferDuration = 5.0
        }
        player?.play()
        displayLink?.isPaused = false
    }
    
    /// Ensures the player respects the current AVAudioSession settings.
    func applyAudioSessionCategory() {
        // AVPlayer doesn't strictly need a method call to "mix", 
        // but we ensure the player's internal state is active if playing.
        if isPlaying() {
            // Re-asserting play state can help if the session change caused a pause
            player?.play()
        }
    }
    
    func pause() {
        player?.pause()
        displayLink?.isPaused = true
    }
    
    func setLooping(_ looping: Bool) { isLooping = looping }
    
    func setVolume(_ volume: Double) { player?.volume = Float(volume) }
    
    func setPlaybackSpeed(_ speed: Double) {
        player?.rate = Float(speed)
    }
    
    func setCaptionOffset(_ offset: Int) {
        captionOffset = offset
    }

    func seek(to position: Int) {
        let time = CMTimeMake(value: Int64(position), timescale: 1000)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func getPosition() -> Int {
        guard let player = player else { return 0 }
        return Int(CMTimeGetSeconds(player.currentTime()) * 1000)
    }
    
    func dispose() {
        // Ensure we are on the main thread for UI cleanup
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.dispose()
            }
            return
        }

        print("NCVP: Player [DISPOSE] textureId: \(textureId)")
        displayLink?.invalidate()
        displayLink = nil
        
        // Remove observers
        playerItem?.removeObserver(self, forKeyPath: "status")
        playerItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
        playerItem?.removeObserver(self, forKeyPath: "presentationSize")
        playerItem?.removeObserver(self, forKeyPath: "duration")
        player?.removeObserver(self, forKeyPath: "rate")
        NotificationCenter.default.removeObserver(self)
        
        // Aggressive resource cleanup
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        
        videoOutput = nil
        playerItem = nil
        player = nil
        
        resourceLoaderDelegate?.cancel()
        resourceLoaderDelegate = nil 
        
        // Break event channel retain cycles
        eventChannel?.setStreamHandler(nil)
        eventChannel = nil
        _eventSink = nil
    }
    
    /// Disposes the AVPlayer and Item but keeps the Texture/Registry alive for re-initialization.
    private func disposePlayerOnly() {
        // Ensure we are on the main thread for UI cleanup
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.disposePlayerOnly()
            }
            return
        }

        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        
        if let item = playerItem {
            item.removeObserver(self, forKeyPath: "status")
            item.removeObserver(self, forKeyPath: "loadedTimeRanges")
            item.removeObserver(self, forKeyPath: "presentationSize")
            item.removeObserver(self, forKeyPath: "duration")
        }
        player?.removeObserver(self, forKeyPath: "rate")
        NotificationCenter.default.removeObserver(self)
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        
        videoOutput = nil
        playerItem = nil
        player = nil
        
        resourceLoaderDelegate?.cancel()
        resourceLoaderDelegate = nil
    }
}

extension FLTVideoPlayer: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self._eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self._eventSink = nil
        return nil
    }
}
