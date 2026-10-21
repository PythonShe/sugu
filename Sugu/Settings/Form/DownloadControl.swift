import AppKit
import SuguEngines

/// The controls for one downloadable item: its size and license, and the
/// action its state allows (download, cancel, remove, retry). VoiceOver
/// reads them as a group named for the item.
@MainActor
final class DownloadControl: NSStackView {
    private let item: ModelLibrary.Item
    private let name: String
    private let model: SettingsModel
    private let detail = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let button = NSButton(title: "", target: nil, action: nil)
    /// Remove, beside Update or Try Again while the item is installed.
    private let removeButton = NSButton(title: String(localized: "Remove"), target: nil, action: nil)

    init(item: ModelLibrary.Item, name: String, model: SettingsModel) {
        self.item = item
        self.name = name
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(name)
        orientation = .horizontal
        spacing = 8
        alignment = .firstBaseline
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.widthAnchor.constraint(equalToConstant: 120).isActive = true
        button.bezelStyle = .push
        button.target = self
        button.action = #selector(buttonPressed)
        removeButton.bezelStyle = .push
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        addArrangedSubview(button)
        addArrangedSubview(removeButton)
        addArrangedSubview(progress)
        addArrangedSubview(detail)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var summary: String {
        let size = model.updateSize(of: item) ?? item.download.size
        return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) · \(item.license)"
    }

    func update() {
        let state = model.state(of: item)
        progress.isHidden = true
        detail.textColor = .secondaryLabelColor
        detail.stringValue = summary
        button.isEnabled = true
        removeButton.isHidden = true
        switch state {
        case .notInstalled:
            button.title = String(localized: "Download")
        case .downloading(let fraction):
            button.title = String(localized: "Cancel")
            progress.isHidden = false
            progress.isIndeterminate = false
            progress.doubleValue = fraction
            detail.stringValue = fraction.formatted(.percent.precision(.fractionLength(0)))
        case .installing:
            button.title = String(localized: "Cancel")
            button.isEnabled = false
            progress.isHidden = false
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            detail.stringValue = ""
        case .installed:
            let hasUpdate = model.updateSize(of: item) != nil
            button.title = hasUpdate ? String(localized: "Update") : String(localized: "Remove")
            removeButton.isHidden = !hasUpdate
        case .failed(let failure):
            button.title = String(localized: "Try Again")
            removeButton.isHidden = !model.isInstalled(item)
            detail.stringValue = failure.message
            detail.textColor = .systemRed
        }
        if case .installing = state {} else { progress.stopAnimation(nil) }
    }

    @objc private func buttonPressed() {
        switch model.state(of: item) {
        case .notInstalled, .failed: model.install(item)
        case .downloading, .installing: model.cancel(item)
        case .installed:
            if model.updateSize(of: item) != nil { model.install(item) } else { removePressed() }
        }
    }

    @objc private func removePressed() {
        let model = model, item = item
        NSAlert.confirm(String(localized: "Remove “\(name)”?"), action: String(localized: "Remove"), destructive: true, in: window) {
            model.remove(item)
        }
    }
}

extension ModelLibrary.Failure {
    var message: String {
        switch self {
        case .checksumMismatch: String(localized: "The download did not match the expected file.")
        case .server(let status): HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        case .extraction: String(localized: "The archive could not be opened.")
        case .notEnoughSpace: String(localized: "There is not enough space on the disk.")
        case .other(let description): description
        }
    }
}
