import Foundation
import OSLog

/// Centralised logger: writes to os_log (visible in Xcode console + Console.app)
/// and to a rolling log file in the app's Documents folder.
@MainActor
final class AppLogger: ObservableObject {

    static let shared = AppLogger()

    @Published private(set) var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let tag: String
        let message: String

        var formatted: String {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return "[\(df.string(from: timestamp))] [\(tag)] \(message)"
        }
    }

    private let osLog = Logger(subsystem: "com.jamesbaker.FirebaseViewer", category: "AppLogger")
    private let logFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("FirebaseViewer.log")
    }()

    private init() {}

    // MARK: - Static convenience (callable from any context)

    nonisolated static func log(_ message: String, tag: String = "App") {
        Task { @MainActor in shared._log(message, tag: tag) }
    }

    nonisolated static func error(_ message: String, tag: String = "Error") {
        Task { @MainActor in shared._log("⚠️ " + message, tag: tag) }
    }

    // MARK: - Internal

    private func _log(_ message: String, tag: String) {
        let entry = Entry(timestamp: Date(), tag: tag, message: message)
        let line = entry.formatted
        // os_log (Console.app / Instruments)
        osLog.debug("\(line)")
        // Also print so it shows in Xcode debug console for easy copy-paste
        print(line)
        entries.append(entry)
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        appendToFile(line)
    }

    private func appendToFile(_ line: String) {
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    func clearLogs() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: logFileURL)
    }

    var logFilePath: String { logFileURL.path }
}
