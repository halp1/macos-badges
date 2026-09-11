import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SettingsStore!
    private var manager: MenuBarManager!
    private var windowController: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        store = SettingsStore()
        windowController = SettingsWindowController(store: store)
        manager = MenuBarManager(store: store)
        manager.openSettings = { [weak self] in self?.windowController.show() }

        HotKeyManager.shared.handler = { [weak self] in self?.windowController.toggle() }
        applyHotKey()

        store.changed
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.applyHotKey()
                self?.applyLanguage()
            }
            .store(in: &cancellables)

        if store.data.showSettingsOnStartup || store.data.items.isEmpty || !DockBadgeReader.hasAccess {
            windowController.show()
        }

        // Ask after the window is up, so the system dialog appears over our own UI. This also
        // registers the app in the Accessibility list against its *current* code signature,
        // which is what makes the toggle actually effective.
        if !DockBadgeReader.hasAccess {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                DockBadgeReader.requestAccess()
            }
        }

        if CommandLine.arguments.contains("--selftest-cmdq") {
            runCmdQSelfTest()
        }
    }

    /// Pushes a real ⌘Q key event through AppKit's dispatch chain and reports whether it
    /// reaches the Quit item. Used to verify the shortcut without stealing focus from
    /// whatever app happens to be frontmost.
    private func runCmdQSelfTest() {
        windowController.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let event = NSEvent.keyEvent(
                      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                      windowNumber: window.windowNumber, context: nil,
                      characters: "q", charactersIgnoringModifiers: "q",
                      isARepeat: false, keyCode: 12
                  )
            else {
                print("SELFTEST FAIL: could not build event")
                exit(1)
            }
            // sendEvent is exactly what AppKit calls for a real keystroke, so this exercises
            // the full routing (application → main menu → Quit), not just the menu lookup.
            NSApp.sendEvent(event)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                print("SELFTEST FAIL: still running after ⌘Q")
                exit(1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest-cmdq") {
            print("SELFTEST PASS: ⌘Q terminated the app")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.show()
        return true
    }

    /// An accessory app shows no menu bar, but `NSApp.mainMenu` is still what dispatches
    /// key equivalents while one of our windows is focused — without it there is no ⌘Q,
    /// and text fields get no ⌘C/⌘V either.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu),
                                      keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Badges", action: #selector(NSApplication.hide(_:)),
                                   keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)),
                                   keyEquivalent: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Badges", action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        windowController.show()
    }

    private func applyHotKey() {
        HotKeyManager.shared.update(
            enabled: store.data.shortcutEnabled,
            keyCode: store.data.shortcutKeyCode,
            modifiers: store.data.shortcutModifiers
        )
    }

    private func applyLanguage() {
        if store.data.language == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([store.data.language], forKey: "AppleLanguages")
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsView().environmentObject(store))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Badges Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentView = hosting
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // An accessory app has no Dock presence, so ordering front needs the
        // "regardless" variant plus an explicit activation to take keyboard focus.
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }
}

// `Badges --dump-badges` prints what both readers can see, for troubleshooting
// Accessibility permission without launching the UI.
if CommandLine.arguments.contains("--dump-badges") {
    print("AXIsProcessTrusted: \(DockBadgeReader.isTrustedFlag), can read Dock: \(DockBadgeReader.canReadDock())")

    print("dock badges:")
    let badges = DockBadgeReader.scan()
    if badges.isEmpty {
        print("  none (grant Accessibility access, and make sure a Dock app has an unread count)")
    }
    for (key, value) in badges.sorted(by: { $0.key < $1.key }) {
        print("  \(key) = \(value)")
    }

    // Every running app with a bundle identifier, so an app can be checked for a title
    // count before its detection mode is switched over.
    print("window title counts:")
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    let titles = WindowTitleReader.counts(for: running)
    if titles.isEmpty {
        print("  none (no running app shows a (n) count in its window title)")
    }
    for (key, value) in titles.sorted(by: { $0.key < $1.key }) {
        print("  \(key) = \(value)")
    }
    exit(0)
}

// `Badges --dump-titles` prints the raw window titles of every running app, so it is easy
// to see which ones expose a count that Window Title detection could read.
if CommandLine.arguments.contains("--dump-titles") {
    let running = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .compactMap(\.bundleIdentifier)
    for id in Set(running).sorted() {
        let titles = WindowTitleReader.titles(forBundleIdentifier: id).filter { !$0.isEmpty }
        guard !titles.isEmpty else { continue }
        print(id)
        for title in titles {
            let count = WindowTitleReader.extractCount(from: title)
            print("  \(title)\(count.map { "   -> \($0)" } ?? "")")
        }
    }
    exit(0)
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
