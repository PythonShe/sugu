import AppKit
import SuguCore

/// A bordered table with the standard add and remove buttons under it;
/// Delete removes the selected rows too.
@MainActor
final class TableEditor: NSStackView {
    let table = EditableTableView()
    private let scroll = NSScrollView()
    private let buttons = NSSegmentedControl()
    var onAdd: (() -> Void)?
    var onRemove: (() -> Void)?

    init(height: CGFloat, width: CGFloat = 420) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.style = .fullWidth
        table.rowSizeStyle = .default
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: width),
            scroll.heightAnchor.constraint(equalToConstant: height),
        ])
        buttons.segmentStyle = .smallSquare
        buttons.trackingMode = .momentary
        buttons.segmentCount = 2
        buttons.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "Add")), forSegment: 0)
        buttons.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: String(localized: "Remove")), forSegment: 1)
        buttons.setWidth(24, forSegment: 0)
        buttons.setWidth(24, forSegment: 1)
        buttons.target = self
        buttons.action = #selector(buttonPressed)
        table.onDelete = { [weak self] in
            guard let self, buttons.isEnabled, buttons.isEnabled(forSegment: 1) else { return }
            onRemove?()
        }
        addArrangedSubview(scroll)
        addArrangedSubview(buttons)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setRemoveEnabled(_ enabled: Bool) {
        buttons.setEnabled(enabled, forSegment: 1)
    }

    func setEnabled(_ enabled: Bool) {
        table.isEnabled = enabled
        buttons.isEnabled = enabled
    }

    /// The row's label names the table, which VoiceOver reaches directly.
    override func setAccessibilityLabel(_ accessibilityLabel: String?) {
        table.setAccessibilityLabel(accessibilityLabel)
    }

    @objc private func buttonPressed() {
        switch buttons.selectedSegment {
        case 0: onAdd?()
        case 1: onRemove?()
        default: break
        }
    }

    func addColumn(_ identifier: String, title: String, width: CGFloat, sortKey: String? = nil) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.minWidth = ceil(column.headerCell.cellSize.width) + 12
        column.width = max(width, column.minWidth)
        if let sortKey { column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true) }
        table.addTableColumn(column)
    }
}

/// A table that reports the Delete and Forward Delete keys.
@MainActor
final class EditableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if let onDelete, event.specialKey == .delete || event.specialKey == .deleteForward, !selectedRowIndexes.isEmpty {
            onDelete()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// An app's icon and name, from its bundle identifier.
enum AppInfo {
    static func name(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleIdentifier: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// A table cell with the app's icon and name.
    @MainActor
    static func cell(for bundleIdentifier: String, in table: NSTableView) -> NSTableCellView {
        let identifier = NSUserInterfaceItemIdentifier("AppCell")
        let cell = table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            image.translatesAutoresizingMaskIntoConstraints = false
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.addSubview(text)
            cell.imageView = image
            cell.textField = text
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.imageView?.image = icon(for: bundleIdentifier)
        cell.textField?.stringValue = name(for: bundleIdentifier)
        return cell
    }

    /// Lets the user pick applications; returns their bundle identifiers.
    @MainActor
    static func choose() -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

/// A plain text cell for tables.
@MainActor
func textCell(_ value: String, in table: NSTableView, secondary: Bool = false) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier(secondary ? "SecondaryTextCell" : "TextCell")
    let cell = table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        if secondary { text.textColor = .secondaryLabelColor }
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }()
    cell.textField?.stringValue = value
    return cell
}
