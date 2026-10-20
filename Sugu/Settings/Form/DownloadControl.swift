import AppKit
import SuguEngines

/// The controls for one downloadable item: its size and license, and the
/// action its state allows (download, cancel, remove, retry).
@MainActor
final class DownloadControl: NSStackView {
    private let item: ModelLibrary.Item
    private let model: SettingsModel
    private let detail = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let button = NSButton(title: "", target: nil, action: nil)

    init(item: ModelLibrary.Item, model: SettingsModel) {
        self.item = item
        self.model = model
        super.init(frame: .zero)
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
        addArrangedSubview(button)
        addArrangedSubview(progress)
        addArrangedSubview(detail)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var summary: String {
        "\(ByteCountFormatter.string(fromByteCount: item.download.size, countStyle: .file)) · \(item.license)"
    }

    func update() {
        let state = model.state(of: item)
        progress.isHidden = true
        detail.textColor = .secondaryLabelColor
        detail.stringValue = summary
        button.isEnabled = true
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
            button.title = String(localized: "Remove")
        case .failed(let failure):
            button.title = String(localized: "Retry")
            detail.stringValue = failure.message
            detail.textColor = .systemRed
        }
        if case .installing = state {} else { progress.stopAnimation(nil) }
    }

    @objc private func buttonPressed() {
        switch model.state(of: item) {
        case .notInstalled, .failed: model.install(item)
        case .downloading, .installing: model.cancel(item)
        case .installed: model.remove(item)
        }
    }
}

extension ModelLibrary.Failure {
    var message: String {
        switch self {
        case .checksumMismatch: String(localized: "The download did not match the expected file.")
        case .server(let status): HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        case .extraction: String(localized: "The archive could not be opened.")
        case .other(let description): description
        }
    }
}
