import Foundation

/// Verbose tracing, enabled with `BADGES_DEBUG=1`.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["BADGES_DEBUG"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("[badges] " + message() + "\n").utf8))
    }
}
