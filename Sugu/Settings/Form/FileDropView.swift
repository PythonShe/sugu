import AppKit

/// A view that takes files dropped on it, outlined while they hover. As a
/// well, it is outlined in dashes until then.
@MainActor
final class FileDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var isWell = false {
        didSet { needsDisplay = true }
    }
    private var isTargeted = false {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func files(in info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard onDrop != nil, !files(in: sender).isEmpty else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isTargeted = false
        let urls = files(in: sender)
        guard let onDrop, !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isWell || isTargeted else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        path.lineWidth = isTargeted ? 3 : 1.5
        if !isTargeted { path.setLineDash([6, 4], count: 2, phase: 0) }
        (isTargeted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
    }
}
