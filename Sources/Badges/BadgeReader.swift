import Foundation

/// Gathers both unread-count sources off the main thread and hands back one snapshot.
///
/// Each source is independent — see `DockBadgeReader` and `WindowTitleReader` — and which
/// of the two a given app's count comes from is decided later, by its `DetectionMode`.
final class BadgeReader {
    private let queue = DispatchQueue(label: "com.local.badges.read", qos: .utility)

    struct Snapshot {
        /// Dock badges, keyed by bundle identifier plus `name:<Dock title>` fallback entries.
        var dock: [String: String] = [:]
        /// Window-title counts, keyed by bundle identifier.
        var titles: [String: String] = [:]
        /// True when the Dock actually answered — the only trustworthy access signal.
        var hasAccess = false
    }

    /// Window titles are only read for `titleCandidates`, so apps set to Dock-only detection
    /// cost nothing.
    func read(titleCandidates: Set<String>, _ completion: @escaping (Snapshot) -> Void) {
        queue.async {
            let dock = DockBadgeReader.snapshot()
            let titles = WindowTitleReader.counts(for: titleCandidates)
            let snapshot = Snapshot(dock: dock.badges, titles: titles, hasAccess: dock.hasAccess)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }
}
