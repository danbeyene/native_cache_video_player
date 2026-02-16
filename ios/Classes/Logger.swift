import Foundation

protocol Logger {
    func debug(_ message: String)
    func error(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
}

class DefaultLogger: Logger {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private func getTimestamp() -> String {
        return dateFormatter.string(from: Date())
    }

    func debug(_ message: String) {
        #if DEBUG
        print("\(getTimestamp()) NCVP [DEBUG]: \(message)")
        #endif
    }

    func error(_ message: String) {
        print("\(getTimestamp()) NCVP [ERROR]: \(message)")
    }
    
    func info(_ message: String) {
        print("\(getTimestamp()) NCVP [INFO]: \(message)")
    }

    func warning(_ message: String) {
        print("\(getTimestamp()) NCVP [WARN]: \(message)")
    }
}
