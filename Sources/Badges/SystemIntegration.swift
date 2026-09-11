import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Global hotkey

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func update(enabled: Bool, keyCode: UInt32, modifiers: UInt32) {
        unregister()
        guard enabled, modifiers != 0 else { return }
        installEventHandler()
        let id = EventHotKeyID(signature: OSType(0x4247_4659), id: 1) // 'BGFY'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
    }

    private func installEventHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyManager.shared.handler?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum Shortcut {
    /// Converts AppKit modifier flags to the Carbon bitmask `RegisterEventHotKey` expects.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    static func display(keyCode: UInt32, modifiers: UInt32) -> String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S",
            17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        ]
        return map[code] ?? "Key \(code)"
    }
}

// MARK: - Installed application discovery

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let path: String
}

enum AppScanner {
    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        roots.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)

        var found: [String: InstalledApp] = [:]

        func consider(_ path: String) {
            guard path.hasSuffix(".app"),
                  let bundle = Bundle(path: path),
                  let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier,
                  found[id] == nil
            else { return }
            let name = fm.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "")
            found[id] = InstalledApp(bundleIdentifier: id, name: name, path: path)
        }

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let full = root + "/" + entry
                if entry.hasSuffix(".app") {
                    consider(full)
                } else if let nested = try? fm.contentsOfDirectory(atPath: full) {
                    // One level deep covers vendor folders like /Applications/Microsoft Office.
                    for sub in nested where sub.hasSuffix(".app") {
                        consider(full + "/" + sub)
                    }
                }
            }
        }

        // Anything currently running that lives elsewhere.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let url = app.bundleURL { consider(url.path) }
        }

        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
