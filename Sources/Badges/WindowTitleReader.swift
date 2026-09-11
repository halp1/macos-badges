import AppKit
import ApplicationServices

/// Reads unread counts out of an app's window title.
///
/// Some apps never badge their Dock tile and only ever put the count in the title bar —
/// Signal renders `Signal (1)`. Titles come from the same Accessibility API the Dock
/// reader already needs, so this costs no extra permission.
enum WindowTitleReader {
    /// A parenthesised count anywhere in the title: `Signal (1)`, `(12) Slack`,
    /// `Inbox (1,204) — Mail`.
    private static let pattern = try! NSRegularExpression(pattern: #"\((\d[\d,]*)\)"#)

    static func counts(for bundleIdentifiers: Set<String>) -> [String: String] {
        var out: [String: String] = [:]
        for id in bundleIdentifiers {
            if let count = count(forBundleIdentifier: id) { out[id] = count }
        }
        return out
    }

    static func count(forBundleIdentifier id: String) -> String? {
        titles(forBundleIdentifier: id).lazy.compactMap(extractCount).first
    }

    /// Every window title the app currently shows — what `--dump-titles` reports, so an app
    /// can be checked before its detection mode is switched over.
    static func titles(forBundleIdentifier id: String) -> [String] {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).flatMap {
            titles(of: AXUIElementCreateApplication($0.processIdentifier))
        }
    }

    static func extractCount(from title: String) -> String? {
        let whole = NSRange(title.startIndex..., in: title)
        guard let match = pattern.firstMatch(in: title, range: whole),
              let digits = Range(match.range(at: 1), in: title) else { return nil }
        // `(0)` is an app spelling out that nothing is unread — not a badge worth drawing.
        guard let count = Int(title[digits].replacingOccurrences(of: ",", with: "")), count > 0 else {
            return nil
        }
        return String(count)
    }

    /// The main window first — it is the one that carries the count when an app has several.
    private static func titles(of app: AXUIElement) -> [String] {
        var elements: [AXUIElement] = []
        if let main = element(attribute(app, kAXMainWindowAttribute as String)) {
            elements.append(main)
        }
        if let windows = attribute(app, kAXWindowsAttribute as String) as? [AXUIElement] {
            elements.append(contentsOf: windows)
        }
        return elements.compactMap { attribute($0, kAXTitleAttribute as String) as? String }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// `AXUIElement` is a CoreFoundation type, so narrowing a `CFTypeRef` to one needs a
    /// runtime type check rather than a conditional cast.
    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
