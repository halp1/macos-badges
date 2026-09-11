import AppKit
import SwiftUI

struct AppPickerView: View {
    let onAdd: ([InstalledApp]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var loading = true

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Menu Bar Items").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    chooseManually()
                } label: {
                    Label("Browse…", systemImage: "folder")
                }
                .buttonStyle(.link)
            }
            .padding(14)

            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, selection: $selection) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name).font(.system(size: 13))
                        Spacer()
                        Text(app.bundleIdentifier)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .tag(app.bundleIdentifier)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    onAdd(apps.filter { selection.contains($0.bundleIdentifier) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 480, height: 460)
        .task {
            let found = await Task.detached { AppScanner.installedApps() }.value
            apps = found
            loading = false
        }
    }

    private func chooseManually() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let picked: [InstalledApp] = panel.urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return InstalledApp(bundleIdentifier: id, name: name, path: url.path)
        }
        guard !picked.isEmpty else { return }
        onAdd(picked)
        dismiss()
    }
}
