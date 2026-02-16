import Foundation

enum CacheError: Error {
    case invalidURL(String)
    case downloadFailed(Error)
    case cacheCorrupted(String)
    case networkUnavailable
    case fileSystemError(Error)
    case invalidResponse(Int)
    case invalidContentType(String)
    case general(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .downloadFailed(let error): return "Download failed: \(error.localizedDescription)"
        case .cacheCorrupted(let reason): return "Cache corrupted: \(reason)"
        case .networkUnavailable: return "Network unavailable"
        case .fileSystemError(let error): return "File system error: \(error.localizedDescription)"
        case .invalidResponse(let code): return "Invalid response code: \(code)"
        case .invalidContentType(let type): return "Invalid content type: \(type)"
        case .general(let msg): return msg
        }
    }
}
