import Foundation

/// Verbose tracing, enabled with `BADGEIFY_DEBUG=1`.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["BADGEIFY_DEBUG"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("[badgeify] " + message() + "\n").utf8))
    }
}
