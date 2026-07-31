import AppKit
import ApplicationServices

/// Reads unread badge labels out of the Dock using the Accessibility API.
///
/// Dock tiles expose their badge text as the (undocumented but stable) `AXStatusLabel`
/// attribute, and the app they represent through `AXURL`. That is the only public way to
/// observe another app's badge, so Accessibility permission is required.
final class DockBadgeReader {
    private let queue = DispatchQueue(label: "com.local.badgeify.dock", qos: .utility)

    /// `AXIsProcessTrusted()` is latched at process start: a process that launched before
    /// the user granted access keeps reporting `false` for its whole lifetime. So trust is
    /// determined functionally — by trying a real Accessibility read on the Dock — and the
    /// flag is only a fast path.
    static var hasAccess: Bool { canReadDock() || AXIsProcessTrusted() }

    static var isTrustedFlag: Bool { AXIsProcessTrusted() }

    static func canReadDock() -> Bool {
        guard let dock = dockElement() else { return false }
        return attribute(dock, kAXChildrenAttribute as String) != nil
    }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private static func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        return AXUIElementCreateApplication(dock.processIdentifier)
    }

    /// Relaunches the app — the reliable escape hatch when access was granted while this
    /// process was already running and the API keeps reporting otherwise.
    @MainActor
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    struct Snapshot {
        /// Keys are bundle identifiers, plus `name:<Dock title>` entries as a fallback for
        /// apps whose bundle can't be resolved.
        var badges: [String: String] = [:]
        /// True when the Dock actually answered — the only trustworthy access signal.
        var hasAccess = false
    }

    func read(_ completion: @escaping (Snapshot) -> Void) {
        queue.async {
            let result = Self.snapshot()
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func snapshot() -> Snapshot {
        guard let dock = dockElement(),
              let children = attribute(dock, kAXChildrenAttribute as String) as? [AXUIElement]
        else { return Snapshot() }

        var out: [String: String] = [:]
        for child in children {
            walk(child, depth: 1, into: &out)
        }
        return Snapshot(badges: out, hasAccess: true)
    }

    static func scan() -> [String: String] { snapshot().badges }

    private static func walk(_ element: AXUIElement, depth: Int, into out: inout [String: String]) {
        guard depth <= 4 else { return }

        if let label = attribute(element, "AXStatusLabel") as? String,
           !label.trimmingCharacters(in: .whitespaces).isEmpty {
            if let url = attribute(element, "AXURL") as? NSURL,
               let id = Bundle(url: url as URL)?.bundleIdentifier {
                out[id] = label
            }
            if let title = attribute(element, kAXTitleAttribute as String) as? String {
                out["name:" + title] = label
            }
        }

        if let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children {
                walk(child, depth: depth + 1, into: &out)
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// True when the app has a Dock tile at all — badges are unreadable otherwise.
    static func isInDock(bundleIdentifier: String) -> Bool {
        guard let persistent = UserDefaults(suiteName: "com.apple.dock")?
            .array(forKey: "persistent-apps") as? [[String: Any]] else { return false }
        for entry in persistent {
            guard let tile = entry["tile-data"] as? [String: Any] else { continue }
            if let id = tile["bundle-identifier"] as? String, id == bundleIdentifier { return true }
            if let fileData = tile["file-data"] as? [String: Any],
               let path = fileData["_CFURLString"] as? String,
               let bundle = Bundle(url: URL(fileURLWithPath: path.replacingOccurrences(of: "file://", with: ""))),
               bundle.bundleIdentifier == bundleIdentifier {
                return true
            }
        }
        return false
    }
}
