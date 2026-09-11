import AppKit
import Combine
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, advanced, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .advanced: return "Advanced"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .advanced: return "cube.fill"
        case .updates: return "lightbulb.max.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var tab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(tab: $tab)
                .frame(width: 205)
                .background(VisualEffectBackground(material: .sidebar))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(tab.title)
                        .font(.system(size: 26, weight: .semibold))
                        .padding(.bottom, 4)

                    switch tab {
                    case .general: GeneralPane()
                    case .advanced: AdvancedPane()
                    case .updates: UpdatesPane()
                    case .about: AboutPane()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.paneBackground)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 560, idealHeight: 640)
    }
}

private struct Sidebar: View {
    @Binding var tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 46)

            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14))
                            .frame(width: 20)
                            .foregroundStyle(tab == item ? Color.white : Color.secondary)
                        Text(item.title)
                            .font(.system(size: 15))
                            .foregroundStyle(tab == item ? Color.white : Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tab == item ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                if let url = URL(string: "https://github.com/") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                    Text("Feedback").font(.system(size: 14))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var selection = Set<UUID>()
    @State private var showingPicker = false
    @State private var trusted = DockBadgeReader.hasAccess
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !trusted {
                PermissionBanner(trusted: $trusted)
            }

            Card {
                SettingsRow(title: "Open at login") {
                    Toggle("", isOn: Binding(
                        get: { store.data.openAtLogin },
                        set: { newValue in
                            store.data.openAtLogin = newValue
                            loginError = LaunchAtLogin.set(newValue)
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "Show settings window on startup") {
                    Toggle("", isOn: $store.data.showSettingsOnStartup)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if let loginError {
                Text(loginError)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(
                    text: "Menu Bar Items",
                    trailing: "\(store.data.items.filter(\.enabled).count) / \(store.data.items.count)"
                )

                Card {
                    List(selection: $selection) {
                        ForEach(store.data.items) { item in
                            ItemRow(item: item)
                                .listRowSeparator(.visible)
                        }
                        .onMove { from, to in
                            store.data.items.move(fromOffsets: from, toOffset: to)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: 216)
                    .overlay {
                        if store.data.items.isEmpty {
                            Text("No apps yet — click + to add one.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    HStack(spacing: 2) {
                        Button {
                            showingPicker = true
                        } label: {
                            Image(systemName: "plus").frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Add app")

                        Button {
                            store.remove(ids: selection)
                            selection = []
                        } label: {
                            Image(systemName: "minus").frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(selection.isEmpty)
                        .help("Remove selected")

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(Color.primary.opacity(0.05))
                }
            }

            Text("Drag to reorder. Each app's count comes from its Dock badge or from the (\u{2026}) in its window title — on Auto, whichever answers first. Use Window Title for apps like Signal that never badge their Dock tile.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showingPicker) {
            AppPickerView { picked in
                store.add(picked.map {
                    MenuBarItem(bundleIdentifier: $0.bundleIdentifier, name: $0.name, path: $0.path)
                })
            }
        }
        .onAppear {
            trusted = DockBadgeReader.hasAccess
            store.data.openAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct ItemRow: View {
    @EnvironmentObject var store: SettingsStore
    let item: MenuBarItem
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Image(nsImage: IconRenderer.appIcon(for: item))
                .resizable()
                .frame(width: 22, height: 22)

            Text(item.name).font(.system(size: 13))

            Spacer()

            Button {
                showingInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                ItemInfo(item: item)
            }

            Picker("", selection: store.detectionBinding(for: item.id)) {
                ForEach(DetectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 124)
            .help(item.detection.detail)

            Toggle("", isOn: store.binding(for: item.id))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}

private struct ItemInfo: View {
    let item: MenuBarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name).font(.system(size: 13, weight: .semibold))
            Label(item.bundleIdentifier, systemImage: "shippingbox")
            Label(item.isRunning ? "Running" : "Not running",
                  systemImage: item.isRunning ? "play.circle" : "stop.circle")
            Label(item.detection.detail, systemImage: "scope")
            if item.detection.readsDock,
               !DockBadgeReader.isInDock(bundleIdentifier: item.bundleIdentifier) {
                Label(item.detection == .dockBadge
                        ? "Not in the Dock — its badge can't be read"
                        : "Not in the Dock — only its window title can be read",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if item.detection.readsTitle, !item.isRunning {
                Label("Not running — no window title to read", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !item.path.isEmpty {
                Text(item.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }
}

private struct PermissionBanner: View {
    @Binding var trusted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access required").font(.system(size: 13, weight: .medium))
                Text("Badges reads unread counts from the Dock and from app window titles, both of which need Accessibility permission. If you just granted it, relaunch — macOS only reports the change to newly started processes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button("Grant Access…") {
                    DockBadgeReader.requestAccess()
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Already granted? Relaunch") { DockBadgeReader.relaunchApp() }
                    .font(.system(size: 11))
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // The banner clears itself once a real Dock read succeeds.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if DockBadgeReader.hasAccess { trusted = true }
        }
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                SettingsRow(title: "Language") {
                    Picker("", selection: $store.data.language) {
                        Text("System Default").tag("system")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            Card {
                SettingsRow(title: "Icon size", info: "How large each app icon is drawn in the menu bar.") {
                    OptionPicker(value: $store.data.iconSize)
                }
                RowDivider()
                SettingsRow(title: "Unread status refresh rate") {
                    OptionPicker(value: $store.data.refreshRate)
                }
                RowDivider()
                SettingsRow(title: "Unread activity animation",
                            info: "Animate the badge while there are unread items.") {
                    OptionPicker(value: $store.data.unreadAnimation)
                }
                RowDivider()
                SettingsRow(title: "When there are no unread items") {
                    OptionPicker(value: $store.data.whenNoUnread)
                }
                RowDivider()
                SettingsRow(title: "When not running") {
                    OptionPicker(value: $store.data.whenNotRunning)
                }
            }

            Card {
                SettingsRow(title: "Settings window shortcut") {
                    HStack(spacing: 10) {
                        ShortcutRecorder(
                            keyCode: $store.data.shortcutKeyCode,
                            modifiers: $store.data.shortcutModifiers,
                            enabled: store.data.shortcutEnabled
                        )
                        Toggle("", isOn: $store.data.shortcutEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                RowDivider()
                SettingsRow(title: "When clicking an app icon") {
                    OptionPicker(value: $store.data.clickBehavior)
                }
            }

            Card {
                SettingsRow(title: "Settings backup") {
                    HStack(spacing: 8) {
                        Button("Import") { importSettings() }
                        Button("Export") { exportSettings() }
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Badges Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "Exported to \(url.lastPathComponent)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importSettings(from: url)
            message = "Imported \(url.lastPathComponent)."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Updates

private struct UpdatesPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var status = "Badges is up to date."
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                SettingsRow(title: "Automatically check for updates") {
                    Toggle("", isOn: $store.data.autoCheckUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "Current version") {
                    Text(AppInfo.version).foregroundStyle(.secondary)
                }
                RowDivider()
                SettingsRow(title: status) {
                    Button(checking ? "Checking…" : "Check Now") {
                        checking = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            checking = false
                            status = "Badges is up to date."
                        }
                    }
                    .disabled(checking)
                }
            }

            Text("This build has no update server configured; \"Check Now\" is a no-op.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                HStack(spacing: 16) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Badges").font(.system(size: 20, weight: .semibold))
                        Text("Version \(AppInfo.version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("App icons with unread badges, in your menu bar.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
            }

            Card {
                SettingsRow(title: "Accessibility permission") {
                    Text(DockBadgeReader.hasAccess ? "Granted" : "Not granted")
                        .foregroundStyle(DockBadgeReader.hasAccess ? .green : .orange)
                }
                RowDivider()
                SettingsRow(title: "Badge source") {
                    Text("Dock tiles (AXStatusLabel)").foregroundStyle(.secondary)
                }
                RowDivider()
                SettingsRow(title: "Quit Badges") {
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
    }
}

enum AppInfo {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
