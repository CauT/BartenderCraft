import AppKit
import BarGardenCore

@MainActor
final class MenuBarAppearanceView: NSView {
    var style: MenuBarAppearance { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }

    init(style: MenuBarAppearance, frame: NSRect) {
        self.style = style
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard style.background != .system else { return }
        let border = CGFloat(style.effectiveBorderWidth)
        let rect = bounds.insetBy(dx: border / 2, dy: border / 2)
        let radius = style.effectiveRadius(height: rect.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let first = color(style.primary).withAlphaComponent(style.effectiveOpacity)
        if style.background == .gradient {
            NSGradient(starting: first, ending: color(style.secondary).withAlphaComponent(style.effectiveOpacity))?.draw(in: rect, angle: 0)
        } else {
            first.setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if border > 0 {
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            path.lineWidth = border
            path.stroke()
        }
    }

    private func color(_ tone: MenuBarTone) -> NSColor {
        switch tone {
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .violet: .systemPurple
        case .graphite: .systemGray
        }
    }
}
