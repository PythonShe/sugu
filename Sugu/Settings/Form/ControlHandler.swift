import AppKit

/// Target object that forwards a control's action to a closure.
@MainActor
final class ControlHandler: NSObject {
    private let handler: (NSControl) -> Void

    nonisolated(unsafe) private static var key: UInt8 = 0

    private init(_ handler: @escaping (NSControl) -> Void) {
        self.handler = handler
    }

    /// Makes `handler` the control's action. The control owns the target,
    /// so a reused table cell replaces its handler instead of adding one.
    static func attach(_ handler: @escaping (NSControl) -> Void, to control: NSControl) {
        let target = ControlHandler(handler)
        objc_setAssociatedObject(control, &key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        control.target = target
        control.action = #selector(controlDidAct(_:))
    }

    /// Not `perform(_:)`, which `#selector` resolves to NSObject's
    /// `performSelector:`.
    @objc private func controlDidAct(_ sender: Any?) {
        guard let control = sender as? NSControl else { return }
        handler(control)
    }
}
