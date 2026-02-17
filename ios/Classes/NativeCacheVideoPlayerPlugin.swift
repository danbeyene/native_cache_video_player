import Flutter
import UIKit
import AVFoundation

/// The main plugin class for the Native Cache Video Player iOS implementation.
///
/// This class handles the registration of the plugin with the Flutter registrar 
/// and dispatches method calls from Dart to the appropriate player instances.
public class NativeCacheVideoPlayerPlugin: NSObject, FlutterPlugin {
    private let registrar: FlutterPluginRegistrar
    private var players = [Int64: FLTVideoPlayer]()
    private var playerOrder = [Int64]() // Track LRU order (end is most recent)
    private let playersQueue = DispatchQueue(label: "native_cache_video_player.playersQueue")
    private let MAX_PLAYERS = 4

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
        setupMemoryWarningObserver()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "native_cache_video_player", binaryMessenger: registrar.messenger())
        let instance = NativeCacheVideoPlayerPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        playersQueue.async { [weak self] in
            guard let self = self else { return }
            print("NCVP: [MEMORY] Low memory warning. Purging all paused players.")
            
            // Dispose all players that are not currently playing
            // Note: We can only safely dispose on main thread if needed, 
            // but FLTVideoPlayer.dispose handles its own thread safety/cleanup.
            var keysToRemove = [Int64]()
            for (textureId, player) in self.players {
                if !player.isPlaying() {
                    keysToRemove.append(textureId)
                }
            }
            
            for textureId in keysToRemove {
                if let player = self.players.removeValue(forKey: textureId) {
                    self.playerOrder.removeAll { $0 == textureId }
                    print("NCVP: [MEMORY] Evicting idle player \(textureId)")
                    DispatchQueue.main.async {
                        self.registrar.textures().unregisterTexture(textureId)
                        player.dispose()
                    }
                }
            }
        }
    }

    /// Dispatches method calls from the Flutter layer to the appropriate handler.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            result(nil)
        case "updateConfig":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "invalid_args", message: "Arguments missing", details: nil))
                return
            }
            let max = args["maxCacheSize"] as? Int64 ?? (500 * 1024 * 1024)
            let concurrent = args["concurrentPrecache"] as? Int ?? 2
            let concurrentDuringPlaybackDownload = args["concPrecacheDuringPlaybackDownload"] as? Int ?? 0
            
            CacheManager.shared.updateConfig(maxSize: max, concurrent: concurrent, concurrentWhilePlaying: concurrentDuringPlaybackDownload)
            result(nil)
        case "create":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "invalid_args", message: "Arguments are missing", details: nil))
                return
            }
            create(args: args, result: result)
        case "setMixWithOthers":
            guard let args = call.arguments as? [String: Any],
                  let mixWithOthers = args["mixWithOthers"] as? Bool else {
                result(FlutterError(code: "invalid_args", message: "mixWithOthers argument missing", details: nil))
                return
            }
            let session = AVAudioSession.sharedInstance()
            do {
                if mixWithOthers {
                    try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
                } else {
                    try session.setCategory(.playback, mode: .default, options: [])
                }
                result(nil)
            } catch {
                result(FlutterError(code: "set_category_error", message: error.localizedDescription, details: nil))
            }
        case "clearAllCache":
            playersQueue.async {
                CacheManager.shared.clearAllCache { cleared, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            result(FlutterError(code: "cache_error", message: "Failed to clear cache: \(error.localizedDescription)", details: nil))
                        } else {
                            result(cleared)
                        }
                    }
                }
            }
        case "enforceCacheLimit":
            if let args = call.arguments as? [String: Any], let max = args["maxCacheSize"] as? Int64 {
                playersQueue.async {
                    CacheManager.shared.enforceCacheLimit(maxSize: max) { removed, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                result(FlutterError(code: "cache_error", message: "Failed to enforce cache limit: \(error.localizedDescription)", details: nil))
                            } else {
                                result(removed)
                            }
                        }
                    }
                }
            } else {
                 result(FlutterError(code: "invalid_args", message: "maxCacheSize missing", details: nil))
            }
        case "removeFile":
             if let args = call.arguments as? [String: Any], let url = args["url"] as? String {
                playersQueue.async {
                    CacheManager.shared.removeFile(for: url) { removed, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                result(FlutterError(code: "cache_error", message: "Failed to remove file: \(error.localizedDescription)", details: nil))
                            } else {
                                result(removed)
                            }
                        }
                    }
                }
            } else {
                 result(FlutterError(code: "invalid_args", message: "url missing", details: nil))
            }
        default:
            guard let args = call.arguments as? [String: Any],
                  let textureId = args["textureId"] as? Int64 else {
                result(FlutterMethodNotImplemented)
                return
            }
            
            playersQueue.async { [weak self] in
                guard let self = self else { return }
                guard let player = self.players[textureId] else {
                    // Player was already disposed (e.g. by LRU eviction or memory pressure).
                    // Return success instead of an error – the caller's intent is satisfied.
                    print("NCVP: [WARN] No player found for textureId \(textureId) (already disposed). Ignoring \(call.method).")
                    DispatchQueue.main.async {
                        result(nil)
                    }
                    return
                }
                
                // Update LRU order
                self.playerOrder.removeAll { $0 == textureId }
                self.playerOrder.append(textureId)
                
                if call.method == "setCaptionOffset" {
                    if let offset = args["offset"] as? Int {
                        player.setCaptionOffset(offset)
                    }
                    DispatchQueue.main.async {
                        result(nil)
                    }
                    return
                }
                
                if call.method == "dispose" {
                    let removedPlayer = self.players.removeValue(forKey: textureId)
                    self.playerOrder.removeAll { $0 == textureId }
                    
                    if let player = removedPlayer {
                        DispatchQueue.main.async {
                            self.registrar.textures().unregisterTexture(textureId)
                            player.dispose() // now guaranteed on main thread
                        }
                    } else {
                        // Player already gone – just return success (no error)
                        DispatchQueue.main.async {
                            result(nil)
                        }
                    }
                    return
                }
                
                player.handle(call) { playerResult in
                    DispatchQueue.main.async {
                        result(playerResult)
                    }
                }
            }
        }
    }
    
    /// Creates a new player instance and registers it with the Flutter texture registry.
    private func create(args: [String: Any], result: @escaping FlutterResult) {
        guard let uri = args["uri"] as? String else {
             result(FlutterError(code: "invalid_args", message: "URI is required", details: nil))
             return
        }
        
        let assetName = args["asset"] as? String
        let packageName = args["package"] as? String
        let httpHeaders = args["httpHeaders"] as? [String: String] ?? [:]
        
        // Offload player setup to background
        playersQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Limit concurrent players
            if self.players.count >= self.MAX_PLAYERS {
                if let eldestId = self.playerOrder.first {
                    print("NCVP: [CONCURRENCY] Evicting oldest player \(eldestId) due to limit (\(self.MAX_PLAYERS))")
                    if let eldestPlayer = self.players.removeValue(forKey: eldestId) {
                        self.playerOrder.removeFirst()
                        DispatchQueue.main.async {
                            self.registrar.textures().unregisterTexture(eldestId)
                            eldestPlayer.dispose()
                        }
                    }
                }
            }
            
            var finalUri = uri
            if let assetName = assetName {
                let assetKey: String
                if let packageName = packageName {
                    assetKey = self.registrar.lookupKey(forAsset: assetName, fromPackage: packageName)
                } else {
                    assetKey = self.registrar.lookupKey(forAsset: assetName)
                }
                
                if let path = Bundle.main.path(forResource: assetKey, ofType: nil) {
                    finalUri = URL(fileURLWithPath: path).absoluteString
                }
            }
            
            let player = FLTVideoPlayer(
                uri: finalUri,
                registrar: self.registrar,
                httpHeaders: httpHeaders
            )
            
            DispatchQueue.main.async {
                let textureId = self.registrar.textures().register(player)
                player.textureId = textureId
                player.setupEventChannel(textureId: textureId)
                
                self.playersQueue.async {
                    self.players[textureId] = player
                    self.playerOrder.append(textureId)
                    DispatchQueue.main.async {
                        result(["textureId": textureId])
                    }
                }
            }
        }
    }
}
