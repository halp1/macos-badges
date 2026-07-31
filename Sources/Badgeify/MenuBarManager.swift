import AppKit
import Combine

@MainActor
final class MenuBarManager {
    private let store: SettingsStore
    private let reader = DockBadgeReader()
    private var managed: [ManagedItem] = []
    private var badges: [String: String] = [:]
    private(set) var hasAccess = false
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var phase = 0
    private var cancellables = Set<AnyCancellable>()
    private var lastLayout: [String] = []

    /// Set by the app delegate so right-click menus can open Settings.
    var openSettings: (() -> Void)?

    init(store: SettingsStore) {
        self.store = store

        store.changed
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] in self?.apply() }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        apply()
    }

    // MARK: - Reconcile

    func apply() {
        let layout = enabledItems.map { "\($0.id)|\($0.bundleIdentifier)" }
        if layout != lastLayout {
            rebuild()
            lastLayout = layout
        } else {
            for m in managed {
                if let fresh = store.data.items.first(where: { $0.id == m.config.id }) {
                    m.config = fresh
                }
            }
        }
        restartTimers()
        refresh()
    }

    private var enabledItems: [MenuBarItem] {
        store.data.items.filter(\.enabled)
    }

    private func rebuild() {
        for m in managed {
            NSStatusBar.system.removeStatusItem(m.statusItem)
        }
        managed = []

        // macOS inserts each new status item to the left of the previous one, so build
        // back-to-front to end up with the same order as the settings list.
        for config in enabledItems.reversed() {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let m = ManagedItem(config: config, statusItem: statusItem, manager: self)
            statusItem.button?.target = m
            statusItem.button?.action = #selector(ManagedItem.clicked(_:))
            statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem.button?.imagePosition = .imageOnly
            managed.insert(m, at: 0)
        }
    }

    private func restartTimers() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: store.data.refreshRate.interval,
                                            repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        animationTimer?.invalidate()
        guard store.data.unreadAnimation != .none else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase += 1
                self.redraw()
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        reader.read { [weak self] snapshot in
            guard let self else { return }
            self.badges = snapshot.badges
            self.hasAccess = snapshot.hasAccess
            Log.debug("access=\(snapshot.hasAccess) badges=\(snapshot.badges)")
            // Recorded so `defaults read com.local.badgeify diagnostics` reports the state of
            // the real app process. Running the binary from a terminal is misleading: TCC
            // attributes those calls to the terminal, which may have its own grant.
            UserDefaults.standard.set(
                "access=\(snapshot.hasAccess) badges=\(snapshot.badges.count) items=\(self.managed.count)",
                forKey: "diagnostics"
            )
            self.redraw()
        }
    }

    private func badge(for config: MenuBarItem) -> String? {
        badges[config.bundleIdentifier] ?? badges["name:" + config.name]
    }

    private func redraw() {
        let settings = store.data
        for m in managed {
            let config = m.config
            let badge = self.badge(for: config)
            let running = config.isRunning

            var hidden = false
            var dimmed = false

            if !running {
                switch settings.whenNotRunning {
                case .alwaysShow: break
                case .dim: dimmed = true
                case .hide: hidden = true
                }
            }
            if badge == nil {
                switch settings.whenNoUnread {
                case .alwaysShow: break
                case .dim: dimmed = true
                case .hide: hidden = true
                }
            }

            m.statusItem.isVisible = !hidden
            guard !hidden else { continue }

            let image = IconRenderer.statusImage(for: config, options: .init(
                size: settings.iconSize.points,
                badge: badge,
                dimmed: dimmed,
                animation: settings.unreadAnimation,
                phase: phase
            ))
            m.statusItem.button?.image = image
            m.statusItem.button?.toolTip = badge.map { "\(config.name) — \($0)" } ?? config.name
            Log.debug("draw \(config.name): badge=\(badge ?? "nil") dimmed=\(dimmed) size=\(image.size) visible=\(m.statusItem.isVisible)")
        }
    }

    // MARK: - Actions

    fileprivate func handleClick(_ m: ManagedItem, event: NSEvent?) {
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRightClick {
            showMenu(for: m)
        } else {
            activate(m.config)
        }
    }

    private func activate(_ config: MenuBarItem) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: config.bundleIdentifier)

        guard let app = running.first else {
            guard let url = config.url else { return }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            return
        }

        switch store.data.clickBehavior {
        case .showOnly:
            app.unhide()
            app.activate(options: [.activateAllWindows])
        case .showOrHide:
            if app.isActive {
                app.hide()
            } else {
                app.unhide()
                app.activate(options: [.activateAllWindows])
            }
        case .showAndHideOthers:
            app.unhide()
            app.activate(options: [.activateAllWindows])
            for other in NSWorkspace.shared.runningApplications
            where other.activationPolicy == .regular
                && other.processIdentifier != app.processIdentifier
                && other.bundleIdentifier != Bundle.main.bundleIdentifier {
                other.hide()
            }
        }
    }

    private func showMenu(for m: ManagedItem) {
        let config = m.config
        let menu = NSMenu()

        let badgeText = badge(for: config)
        let header = NSMenuItem(title: badgeText.map { "\(config.name) — \($0) unread" } ?? config.name,
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let open = NSMenuItem(title: config.isRunning ? "Bring to Front" : "Launch \(config.name)",
                              action: #selector(ManagedItem.openApp), keyEquivalent: "")
        open.target = m
        menu.addItem(open)

        if config.isRunning {
            let quit = NSMenuItem(title: "Quit \(config.name)", action: #selector(ManagedItem.quitApp),
                                  keyEquivalent: "")
            quit.target = m
            menu.addItem(quit)
        }

        menu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Remove from Menu Bar", action: #selector(ManagedItem.disableSelf),
                                  keyEquivalent: "")
        hideItem.target = m
        menu.addItem(hideItem)

        let settings = NSMenuItem(title: "Badgeify Settings…", action: #selector(ManagedItem.showSettings),
                                  keyEquivalent: ",")
        settings.target = m
        menu.addItem(settings)

        menu.addItem(.separator())
        let quitSelf = NSMenuItem(title: "Quit Badgeify", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitSelf.target = NSApp
        menu.addItem(quitSelf)

        m.statusItem.menu = menu
        m.statusItem.button?.performClick(nil)
        m.statusItem.menu = nil
    }

    fileprivate func openApp(_ config: MenuBarItem) { activate(config) }

    fileprivate func quitApp(_ config: MenuBarItem) {
        NSRunningApplication.runningApplications(withBundleIdentifier: config.bundleIdentifier)
            .forEach { $0.terminate() }
    }

    fileprivate func disable(_ config: MenuBarItem) {
        store.setEnabled(false, for: config.id)
    }

    fileprivate func requestSettings() { openSettings?() }
}

// MARK: - Per-item controller

@MainActor
private final class ManagedItem: NSObject {
    var config: MenuBarItem
    let statusItem: NSStatusItem
    private weak var manager: MenuBarManager?

    init(config: MenuBarItem, statusItem: NSStatusItem, manager: MenuBarManager) {
        self.config = config
        self.statusItem = statusItem
        self.manager = manager
    }

    @objc func clicked(_ sender: Any?) {
        manager?.handleClick(self, event: NSApp.currentEvent)
    }

    @objc func openApp() { manager?.openApp(config) }
    @objc func quitApp() { manager?.quitApp(config) }
    @objc func disableSelf() { manager?.disable(config) }
    @objc func showSettings() { manager?.requestSettings() }
}
