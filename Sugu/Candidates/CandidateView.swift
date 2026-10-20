import AppKit
import CoreText
import SuguCore
import SuguInput

/// Draws one page of candidates with Core Text. Layout is computed once
/// per update; drawing only places the prepared lines.
final class CandidateView: NSView {
    struct Style: Equatable {
        var layout: CandidateLayout
        var fontSize: CGFloat
    }

    var onSelect: ((Int) -> Void)?
    var onTurnPage: ((Int) -> Void)?
    /// VoiceOver labels of the page buttons.
    var pageLabels = (previous: "", next: "")

    private struct Row {
        var frame: NSRect
        var label: CTLine
        var text: CTLine
        var annotation: CTLine?
        var labelX: CGFloat
        var textX: CGFloat
        var annotationX: CGFloat
    }

    private enum Metrics {
        static let inset: CGFloat = 5
        static let horizontalPadding: CGFloat = 7
        static let verticalPadding: CGFloat = 4
        static let labelGap: CGFloat = 5
        static let annotationGap: CGFloat = 6
        static let highlightRadius: CGFloat = 6
        /// Longest a candidate is drawn, in multiples of the font size;
        /// longer ones are shortened in the middle.
        static let maxTextEms: CGFloat = 20
    }

    private var presentation: CandidatePresentation?
    private var style = Style(layout: .vertical, fontSize: 16)
    private var rows: [Row] = []
    private var baseline: CGFloat = 0
    private var pager: (previous: NSRect, next: NSRect)?
    private var increasedContrast = false
    private var scrollDistance: CGFloat = 0
    private var scrollTurned = false
    private var hoveredIndex: Int?
    /// Built when assistive technology asks, after each update.
    private var accessibilityElements: [Element]?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays out `presentation` and returns the size it needs.
    func update(_ presentation: CandidatePresentation, style: Style) -> NSSize {
        self.presentation = presentation
        self.style = style
        increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        let textFont = NSFont.systemFont(ofSize: style.fontSize)
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: (style.fontSize * 0.75).rounded(), weight: .regular)
        let annotationFont = NSFont.systemFont(ofSize: (style.fontSize * 0.72).rounded())

        var lines: [(label: CTLine, text: CTLine, annotation: CTLine?)] = []
        var ascent = textFont.ascender, descent = -textFont.descender
        let maxTextWidth = (style.fontSize * Metrics.maxTextEms).rounded()
        for (index, candidate) in presentation.candidates.enumerated() {
            let text = Self.truncated(Self.line(candidate.text, font: textFont), to: maxTextWidth, font: textFont)
            let label = Self.line(presentation.labels[index], font: labelFont)
            let annotation = candidate.annotation.map { Self.line($0, font: annotationFont) }
            var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
            _ = CTLineGetTypographicBounds(text, &a, &d, &l)
            ascent = max(ascent, a)
            descent = max(descent, d)
            lines.append((label, text, annotation))
        }
        let rowHeight = ceil(ascent + descent) + Metrics.verticalPadding * 2
        baseline = Metrics.verticalPadding + ceil(ascent)

        rows = []
        var x = Metrics.inset, y = Metrics.inset, widest: CGFloat = 0
        for line in lines {
            let labelWidth = Self.width(line.label)
            let textWidth = Self.width(line.text)
            let annotationWidth = line.annotation.map { Metrics.annotationGap + Self.width($0) } ?? 0
            let width = Metrics.horizontalPadding * 2 + labelWidth + Metrics.labelGap + textWidth + annotationWidth
            let labelX = Metrics.horizontalPadding
            let textX = labelX + labelWidth + Metrics.labelGap
            let row = Row(
                frame: NSRect(x: x, y: y, width: ceil(width), height: rowHeight),
                label: line.label, text: line.text, annotation: line.annotation,
                labelX: labelX, textX: textX, annotationX: textX + textWidth + Metrics.annotationGap
            )
            rows.append(row)
            widest = max(widest, row.frame.width)
            switch style.layout {
            case .vertical: y += rowHeight
            case .horizontal: x += row.frame.width
            }
        }
        if style.layout == .vertical {
            for index in rows.indices { rows[index].frame.size.width = widest }
        }

        var size: NSSize
        switch style.layout {
        case .vertical: size = NSSize(width: Metrics.inset * 2 + widest, height: y + Metrics.inset)
        case .horizontal: size = NSSize(width: x + Metrics.inset, height: Metrics.inset * 2 + rowHeight)
        }
        pager = nil
        if presentation.hasPreviousPage || presentation.hasNextPage {
            let column = ceil(labelFont.pointSize) + Metrics.horizontalPadding
            let right = size.width - Metrics.inset
            let top = Metrics.inset, height = size.height - Metrics.inset * 2
            switch style.layout {
            case .vertical:
                pager = (NSRect(x: right, y: top, width: column, height: height / 2),
                         NSRect(x: right, y: top + height / 2, width: column, height: height / 2))
                size.width += column
            case .horizontal:
                pager = (NSRect(x: right, y: top, width: column, height: height),
                         NSRect(x: right + column, y: top, width: column, height: height))
                size.width += column * 2
            }
        }
        hoveredIndex = nil
        accessibilityElements = nil
        needsDisplay = true
        return size
    }

    private static func line(_ string: String, font: NSFont) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// `line` shortened in the middle to fit `width`. VoiceOver reads the
    /// candidate's full text, not this.
    private static func truncated(_ line: CTLine, to width: CGFloat, font: NSFont) -> CTLine {
        guard Self.width(line) > width else { return line }
        return CTLineCreateTruncatedLine(line, Double(width), .middle, Self.line("…", font: font)) ?? line
    }

    private static func width(_ line: CTLine) -> CGFloat {
        ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let presentation else { return }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, row) in rows.enumerated() {
            let highlighted = index == presentation.highlightedIndex
            if highlighted || index == hoveredIndex {
                (highlighted ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
                NSBezierPath(roundedRect: row.frame, xRadius: Metrics.highlightRadius, yRadius: Metrics.highlightRadius).fill()
            }
            let primary = highlighted ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
            let secondary = highlighted ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : NSColor.secondaryLabelColor
            let y = row.frame.minY + baseline
            draw(row.label, at: NSPoint(x: row.frame.minX + row.labelX, y: y), color: secondary, in: context)
            draw(row.text, at: NSPoint(x: row.frame.minX + row.textX, y: y), color: primary, in: context)
            if let annotation = row.annotation {
                draw(annotation, at: NSPoint(x: row.frame.minX + row.annotationX, y: y), color: secondary, in: context)
            }
        }
        if let pager {
            let vertical = style.layout == .vertical
            drawChevron(vertical ? "chevron.up" : "chevron.left", in: pager.previous, enabled: presentation.hasPreviousPage)
            drawChevron(vertical ? "chevron.down" : "chevron.right", in: pager.next, enabled: presentation.hasNextPage)
        }
        if increasedContrast {
            NSColor.separatorColor.setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: FloatingPanel.cornerRadius, yRadius: FloatingPanel.cornerRadius)
            border.lineWidth = 1
            border.stroke()
        }
    }

    private func draw(_ line: CTLine, at point: NSPoint, color: NSColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func drawChevron(_ name: String, in rect: NSRect, enabled: Bool) {
        let color = enabled ? NSColor.secondaryLabelColor : NSColor.quaternaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: (style.fontSize * 0.6).rounded(), weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    // MARK: Accessibility

    /// A candidate or page button, pressable from VoiceOver.
    /// A candidate or page button, pressable from VoiceOver.
    private final class Element: NSAccessibilityElement {
        private let action: @MainActor @Sendable () -> Void

        init(action: @escaping @MainActor @Sendable () -> Void) {
            self.action = action
        }

        override func accessibilityPerformPress() -> Bool {
            // Accessibility calls arrive on the main thread.
            let action = action
            MainActor.assumeIsolated { action() }
            return true
        }
    }

    override func accessibilityChildren() -> [Any]? {
        if let accessibilityElements { return accessibilityElements }
        guard let presentation else { return [] }
        var elements: [Element] = []
        // Built after the panel is placed; an update rebuilds them.
        func element(_ label: String, rect: NSRect, action: @escaping @MainActor @Sendable () -> Void) -> Element {
            let element = Element(action: action)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(label)
            element.setAccessibilityParent(self)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityFrame(NSAccessibility.screenRect(fromView: self, rect: rect))
            return element
        }
        for (index, row) in rows.enumerated() {
            let candidate = presentation.candidates[index]
            let label = [presentation.labels[index], candidate.text, candidate.annotation].compactMap { $0 }.joined(separator: " ")
            let row = element(label, rect: row.frame) { [weak self] in self?.onSelect?(index) }
            row.setAccessibilitySelected(index == presentation.highlightedIndex)
            elements.append(row)
        }
        if let pager {
            let previous = element(pageLabels.previous, rect: pager.previous) { [weak self] in self?.onTurnPage?(-1) }
            previous.setAccessibilityEnabled(presentation.hasPreviousPage)
            let next = element(pageLabels.next, rect: pager.next) { [weak self] in self?.onTurnPage?(1) }
            next.setAccessibilityEnabled(presentation.hasNextPage)
            elements += [previous, next]
        }
        accessibilityElements = elements
        return elements
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        guard let index = presentation?.highlightedIndex, let elements = accessibilityChildren() as? [Element],
              elements.indices.contains(index) else { return [] }
        return [elements[index]]
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The panel never becomes key, so the hover is tracked always.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHovered(rows.firstIndex { $0.frame.contains(point) })
    }

    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func setHovered(_ index: Int?) {
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let pager {
            if pager.previous.contains(point) { onTurnPage?(-1); return }
            if pager.next.contains(point) { onTurnPage?(1); return }
        }
        if let index = rows.firstIndex(where: { $0.frame.contains(point) }) {
            onSelect?(index)
        }
    }

    /// One page per wheel notch, or per trackpad swipe.
    override func scrollWheel(with event: NSEvent) {
        let delta = style.layout == .vertical ? event.scrollingDeltaY : event.scrollingDeltaX
        if event.phase == [], event.momentumPhase == [] {
            if delta != 0 { onTurnPage?(delta > 0 ? -1 : 1) }
            return
        }
        if event.phase == .began { scrollDistance = 0; scrollTurned = false }
        guard event.momentumPhase == [], !scrollTurned else { return }
        scrollDistance += delta
        if abs(scrollDistance) > 24 {
            scrollTurned = true
            onTurnPage?(scrollDistance > 0 ? -1 : 1)
        }
    }
}
