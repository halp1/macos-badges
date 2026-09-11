import AppKit

enum IconRenderer {
    private static var cache: [String: NSImage] = [:]

    static func appIcon(for item: MenuBarItem) -> NSImage {
        if let cached = cache[item.bundleIdentifier] { return cached }
        let icon: NSImage
        if let url = item.url {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 16, height: 16))
        }
        cache[item.bundleIdentifier] = icon
        return icon
    }

    static func invalidate() { cache.removeAll() }

    struct Options {
        var size: CGFloat
        var badge: String?
        var dimmed: Bool
        var animation: ActivityAnimation
        var phase: Int
    }

    static func statusImage(for item: MenuBarItem, options o: Options) -> NSImage {
        let icon = appIcon(for: item)
        let side = o.size
        // The badge overlaps the icon's top-right corner and hangs half its width past it.
        let geometry = o.badge.map { badgeGeometry(for: $0, iconSide: side) }
        let overhang = (geometry?.size.width ?? 0) / 2
        let canvas = NSSize(width: side + overhang, height: side)

        var bounce: CGFloat = 0
        var badgeScale: CGFloat = 1
        var badgeAlpha: CGFloat = 1

        if o.badge != nil {
            switch o.animation {
            case .none:
                break
            case .bounce:
                let steps: [CGFloat] = [0, -1, -1.5, -1, 0, 0, 0, 0]
                bounce = steps[o.phase % steps.count]
            case .pulse:
                let steps: [CGFloat] = [1, 1.06, 1.12, 1.06, 1, 0.96, 0.94, 0.96]
                badgeScale = steps[o.phase % steps.count]
            case .blink:
                badgeAlpha = (o.phase % 8) < 4 ? 1 : 0
            }
        }

        let image = NSImage(size: canvas, flipped: false) { _ in
            let iconSide = side - 2
            let rect = NSRect(x: 0, y: (side - iconSide) / 2 - bounce, width: iconSide, height: iconSide)
            icon.draw(in: rect, from: .zero, operation: .sourceOver,
                      fraction: o.dimmed ? 0.45 : 1.0, respectFlipped: true, hints: nil)

            if let geometry, badgeAlpha > 0 {
                drawBadge(geometry, in: canvas, scale: badgeScale, alpha: badgeAlpha)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private struct BadgeGeometry {
        var label: String
        var isDot: Bool
        var font: NSFont
        var textSize: NSSize
        var size: NSSize
    }

    private static func badgeGeometry(for text: String, iconSide: CGFloat) -> BadgeGeometry {
        let label = normalize(text)
        let isDot = label.isEmpty
        let fontSize = max(7, (iconSide * 0.42).rounded())
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let textSize = isDot
            ? .zero
            : (label as NSString).size(withAttributes: [.font: font])
        let height = isDot ? (iconSide * 0.36).rounded() : fontSize + 3
        let width = max(height, textSize.width + height * 0.5)
        return BadgeGeometry(label: label, isDot: isDot, font: font,
                             textSize: textSize, size: NSSize(width: width, height: height))
    }

    private static func drawBadge(_ g: BadgeGeometry, in canvas: NSSize,
                                  scale: CGFloat, alpha: CGFloat) {
        let size = NSSize(width: g.size.width * scale, height: g.size.height * scale)
        let rect = NSRect(
            x: canvas.width - (g.size.width + size.width) / 2,
            y: canvas.height - (g.size.height + size.height) / 2,
            width: size.width,
            height: size.height
        )

        NSGraphicsContext.current?.saveGraphicsState()
        let path = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)

        // Thin dark outline so the badge stays legible over light menu bars.
        NSColor.systemRed.withAlphaComponent(alpha).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.3 * alpha).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        if !g.isDot {
            let origin = NSPoint(
                x: rect.midX - g.textSize.width / 2,
                y: rect.midY - g.textSize.height / 2
            )
            (g.label as NSString).draw(at: origin, withAttributes: [
                .font: g.font,
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            ])
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Dock labels can be counts, arbitrary strings, or a bullet for "some activity".
    private static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "•" || trimmed == "●" { return "" }
        if let n = Int(trimmed) { return n > 99 ? "99+" : String(n) }
        return trimmed.count > 4 ? String(trimmed.prefix(4)) : trimmed
    }
}
