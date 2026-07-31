import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Option enums

protocol TitledOption: CaseIterable, Hashable, Identifiable, Codable where AllCases: RandomAccessCollection {
    var title: String { get }
}

extension TitledOption {
    var id: Self { self }
}

enum IconSize: String, TitledOption {
    case small, medium, large

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var points: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 19
        case .large: return 22
        }
    }
}

enum RefreshRate: String, TitledOption {
    case slow, normal, fast, realtime

    var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        case .realtime: return "Realtime"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .slow: return 5
        case .normal: return 2
        case .fast: return 1
        case .realtime: return 0.4
        }
    }
}

enum ActivityAnimation: String, TitledOption {
    case none, bounce, pulse, blink

    var title: String {
        switch self {
        case .none: return "None"
        case .bounce: return "Bounce"
        case .pulse: return "Pulse"
        case .blink: return "Blink"
        }
    }
}

enum EmptyBehavior: String, TitledOption {
    case alwaysShow, dim, hide

    var title: String {
        switch self {
        case .alwaysShow: return "Always Show"
        case .dim: return "Dim Icon"
        case .hide: return "Hide"
        }
    }
}

enum NotRunningBehavior: String, TitledOption {
    case alwaysShow, dim, hide

    var title: String {
        switch self {
        case .alwaysShow: return "Always Show"
        case .dim: return "Dim Icon"
        case .hide: return "Hide"
        }
    }
}

enum ClickBehavior: String, TitledOption {
    case showOnly, showOrHide, showAndHideOthers

    var title: String {
        switch self {
        case .showOnly: return "Show Only"
        case .showOrHide: return "Show or Hide"
        case .showAndHideOthers: return "Show and Hide Others"
        }
    }
}

// MARK: - Menu bar item

struct MenuBarItem: Codable, Identifiable, Hashable {
    var id: UUID
    var bundleIdentifier: String
    var name: String
    var path: String
    var enabled: Bool

    init(id: UUID = UUID(), bundleIdentifier: String, name: String, path: String, enabled: Bool = true) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? bundleIdentifier
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    var url: URL? {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

// MARK: - Settings data

struct SettingsData: Codable {
    // General
    var openAtLogin = false
    var showSettingsOnStartup = true
    var items: [MenuBarItem] = []

    // Advanced
    var language = "system"
    var iconSize: IconSize = .small
    var refreshRate: RefreshRate = .normal
    var unreadAnimation: ActivityAnimation = .none
    var whenNoUnread: EmptyBehavior = .alwaysShow
    var whenNotRunning: NotRunningBehavior = .alwaysShow
    var shortcutEnabled = false
    var shortcutKeyCode: UInt32 = 11 // B
    var shortcutModifiers: UInt32 = 2304 // cmd + option
    var clickBehavior: ClickBehavior = .showOnly

    // Updates
    var autoCheckUpdates = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        openAtLogin = v(.openAtLogin, false)
        showSettingsOnStartup = v(.showSettingsOnStartup, true)
        items = v(.items, [MenuBarItem]())
        language = v(.language, "system")
        iconSize = v(.iconSize, IconSize.small)
        refreshRate = v(.refreshRate, RefreshRate.normal)
        unreadAnimation = v(.unreadAnimation, ActivityAnimation.none)
        whenNoUnread = v(.whenNoUnread, EmptyBehavior.alwaysShow)
        whenNotRunning = v(.whenNotRunning, NotRunningBehavior.alwaysShow)
        shortcutEnabled = v(.shortcutEnabled, false)
        shortcutKeyCode = v(.shortcutKeyCode, UInt32(11))
        shortcutModifiers = v(.shortcutModifiers, UInt32(2304))
        clickBehavior = v(.clickBehavior, ClickBehavior.showOnly)
        autoCheckUpdates = v(.autoCheckUpdates, true)
    }
}

// MARK: - Store

@MainActor
final class SettingsStore: ObservableObject {
    static let defaultsKey = "settings.v1"

    @Published var data: SettingsData {
        didSet { save() }
    }

    /// Bumped whenever the on-disk/UI state changed in a way the menu bar must react to.
    let changed = PassthroughSubject<Void, Never>()

    private var saving = false

    init() {
        if let raw = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else {
            data = SettingsData()
            data.items = SettingsStore.suggestedItems()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.defaultsKey)
        }
        changed.send()
    }

    // MARK: Item helpers

    func add(_ new: [MenuBarItem]) {
        for item in new where !data.items.contains(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
            data.items.append(item)
        }
    }

    func remove(ids: Set<UUID>) {
        data.items.removeAll { ids.contains($0.id) }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let idx = data.items.firstIndex(where: { $0.id == id }) else { return }
        data.items[idx].enabled = enabled
    }

    func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.data.items.first(where: { $0.id == id })?.enabled ?? false },
            set: { self.setEnabled($0, for: id) }
        )
    }

    /// Apps commonly used with badges, if installed — gives a non-empty first run.
    static func suggestedItems() -> [MenuBarItem] {
        let candidates = [
            "com.hnc.Discord", "org.whispersystems.signal-desktop", "com.tinyspeck.slackmacgap",
            "com.apple.mail", "com.apple.MobileSMS",
        ]
        let found: [MenuBarItem] = candidates.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return MenuBarItem(
                bundleIdentifier: id,
                name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                path: url.path
            )
        }
        return Array(found.prefix(3))
    }

    // MARK: Import / export

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: url)
    }

    func importSettings(from url: URL) throws {
        let raw = try Data(contentsOf: url)
        data = try JSONDecoder().decode(SettingsData.self, from: raw)
    }
}
