import AppKit

/// A borderless, non-activating panel near the caret with the system's
/// floating material: Liquid Glass on macOS 26 and later, the menu material
/// before.
final class FloatingPanel: NSPanel {
    static let cornerRadius: CGFloat = {
        if #available(macOS 26, *) { return 12 }
        return 8
    }()

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]

        content.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            contentView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
            content.frame = effect.bounds
            effect.addSubview(content)
            contentView = effect
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Places a panel of `size` below `anchor` (a caret or text rectangle in
    /// screen coordinates), or above it when there is no room below.
    func place(size: NSSize, below anchor: NSRect, leadingInset: CGFloat = 0, gap: CGFloat = 4) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin = NSPoint(x: anchor.minX - leadingInset, y: anchor.minY - gap - size.height)
        if origin.y < visible.minY { origin.y = anchor.maxY + gap }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
