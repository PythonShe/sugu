import AppKit

/// Builds a settings pane as a two-column grid: right-aligned labels and
/// left-aligned controls, the standard macOS settings layout. Every control
/// reads its value through a closure, so `refresh()` brings the pane up to
/// date after a change made elsewhere.
@MainActor
final class SettingsForm {
    let grid: NSGridView
    private var refreshers: [() -> Void] = []
    init() {
        grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
    }

    func refresh() {
        for refresher in refreshers { refresher() }
    }

    /// Runs `update` now and on every refresh.
    func onRefresh(_ update: @escaping () -> Void) {
        refreshers.append(update)
        update()
    }

    // MARK: Rows

    /// Adds a row; `label` names the row or, for later rows of a group, is nil.
    /// A row of several controls is a group VoiceOver reads by the label; a
    /// button with a title keeps the title as its name.
    @discardableResult
    func row(_ label: String?, _ view: NSView) -> NSGridRow {
        let title = label.map { NSTextField(labelWithString: $0) }
        if let label, (view as? NSButton)?.title.isEmpty != false {
            if view is NSStackView && !(view is TableEditor) || view is NSGridView {
                view.setAccessibilityElement(true)
                view.setAccessibilityRole(.group)
            }
            view.setAccessibilityLabel(Self.name(label))
        }
        let row = grid.addRow(with: [title ?? NSGridCell.emptyContentView, view])
        if view is NSScrollView || view is NSStackView && (view as? NSStackView)?.orientation == .vertical {
            row.rowAlignment = .none
            row.yPlacement = .top
        }
        return row
    }

    /// A row label without its colon, as VoiceOver reads it.
    static func name(_ label: String) -> String {
        label.trimmingCharacters(in: CharacterSet(charactersIn: ":："))
    }

    /// Space between groups of rows.
    func gap() {
        let row = grid.addRow(with: [NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        row.height = 8
        row.rowAlignment = .none
    }

    /// A control that spans both columns, left-aligned under the labels.
    func fullWidth(_ view: NSView) {
        let row = grid.addRow(with: [view, NSGridCell.emptyContentView])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        row.cell(at: 0).xPlacement = .fill
        row.rowAlignment = .none
    }

    // MARK: Controls

    @discardableResult
    func checkbox(_ title: String, label: String? = nil, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        bind(box) { set(($0 as? NSButton)?.state == .on) }
        onRefresh { box.state = get() ? .on : .off }
        row(label, box)
        return box
    }

    @discardableResult
    func popUp<Value: Equatable>(_ label: String?, options: [(title: String, value: Value)], get: @escaping () -> Value, set: @escaping (Value) -> Void) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: options.map(\.title))
        bind(popUp) { control in
            let index = (control as? NSPopUpButton)?.indexOfSelectedItem ?? -1
            if options.indices.contains(index) { set(options[index].value) }
        }
        onRefresh { popUp.selectItem(at: options.firstIndex { $0.value == get() } ?? -1) }
        row(label, popUp)
        return popUp
    }

    @discardableResult
    func segmented<Value: Equatable>(_ label: String?, options: [(title: String, value: Value)], get: @escaping () -> Value, set: @escaping (Value) -> Void) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        bind(control) { control in
            let index = (control as? NSSegmentedControl)?.selectedSegment ?? -1
            if options.indices.contains(index) { set(options[index].value) }
        }
        onRefresh { control.selectedSegment = options.firstIndex { $0.value == get() } ?? -1 }
        row(label, control)
        return control
    }

    @discardableResult
    func textField(_ label: String?, placeholder: String? = nil, width: CGFloat = 220, get: @escaping () -> String, set: @escaping (String) -> Void) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        bind(field) { set(($0 as? NSTextField)?.stringValue ?? "") }
        onRefresh { if field.currentEditor() == nil { field.stringValue = get() } }
        row(label, field)
        return field
    }

    @discardableResult
    func button(_ title: String, label: String? = nil, action: @escaping () -> Void) -> NSButton {
        let button = makeButton(title, action: action)
        row(label, button)
        return button
    }

    func makeButton(_ title: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        bind(button) { _ in action() }
        return button
    }

    /// Routes a control's action to a closure.
    func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        ControlHandler.attach(handler, to: control)
    }
}

/// A settings pane: a form inside the pane's margins, refreshed when the
/// model changes.
@MainActor
class SettingsPane: NSViewController {
    let model: SettingsModel
    let form = SettingsForm()

    init(model: SettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Subclasses add their rows here.
    func build() {}

    /// Subclasses react to changes beyond the form's own controls.
    func modelDidChange(_ change: SettingsModel.Change) {}

    /// The view the form sits in; a pane that takes dropped files gives one
    /// that does.
    func makeContainer() -> NSView { NSView() }

    override func loadView() {
        build()
        let container = makeContainer()
        container.addSubview(form.grid)
        NSLayoutConstraint.activate([
            form.grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            form.grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            form.grid.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            form.grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            form.grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            // Every pane's toolbar item fits without an overflow menu: eight
            // English labels need 550.
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
        ])
        view = container
        model.observe { [weak self] change in
            self?.form.refresh()
            self?.modelDidChange(change)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = view.fittingSize
    }

    // MARK: Panels

    func presentError(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Asks before doing something that cannot be undone or that exposes data.
    func confirm(_ message: String, action title: String, destructive: Bool = false, then perform: @escaping () -> Void) {
        NSAlert.confirm(message, action: title, destructive: destructive, in: view.window, then: perform)
    }
}

extension NSAlert {
    /// Asks before doing something that cannot be undone or that exposes
    /// data, as a sheet on `window`.
    @MainActor
    static func confirm(_ message: String, action title: String, destructive: Bool, in window: NSWindow?, then perform: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        // A destructive button takes no Return; Esc still cancels.
        alert.addButton(withTitle: title).hasDestructiveAction = destructive
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard let window else {
            if alert.runModal() == .alertFirstButtonReturn { perform() }
            return
        }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { perform() }
        }
    }
}
