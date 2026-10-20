import AppKit
import InputMethodKit

/// One controller per client connection. It forwards everything to the
/// shared `InputCoordinator`, which owns the single input session.
///
/// InputMethodKit calls controllers on the main thread but its API is not
/// annotated for concurrency, so each entry point hops into the main actor
/// with `MainActor.assumeIsolated`, passing IMK's objects through unchecked
/// bindings.
@objc(SuguInputController)
final class SuguInputController: IMKInputController {
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        nonisolated(unsafe) let event = event, sender = sender, controller = self
        return MainActor.assumeIsolated {
            guard let event, let client = sender as? (any IMKTextInput & NSObjectProtocol) else { return false }
            return AppEnvironment.shared.coordinator.handle(event, client: client, controller: controller)
        }
    }

    override func activateServer(_ sender: Any!) {
        nonisolated(unsafe) let sender = sender, controller = self
        MainActor.assumeIsolated {
            guard let client = sender as? (any IMKTextInput & NSObjectProtocol) else { return }
            AppEnvironment.shared.coordinator.activate(client: client, controller: controller)
        }
    }

    override func deactivateServer(_ sender: Any!) {
        nonisolated(unsafe) let sender = sender
        MainActor.assumeIsolated {
            AppEnvironment.shared.coordinator.deactivate(client: sender)
        }
    }

    override func commitComposition(_ sender: Any!) {
        nonisolated(unsafe) let sender = sender
        MainActor.assumeIsolated {
            AppEnvironment.shared.coordinator.commitComposition(client: sender)
        }
    }

    override func inputControllerWillClose() {
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated {
            AppEnvironment.shared.coordinator.close(controller: controller)
        }
    }

    override func hidePalettes() {
        MainActor.assumeIsolated {
            AppEnvironment.shared.coordinator.hidePalettes()
        }
        super.hidePalettes()
    }

    override func menu() -> NSMenu! {
        nonisolated(unsafe) var menu: NSMenu?
        MainActor.assumeIsolated {
            menu = AppEnvironment.shared.inputMenu.make()
        }
        return menu
    }

    // IMK sends menu actions to the controller with a dictionary whose
    // kIMKCommandMenuItemName entry is the chosen item.
    @objc func performMenuAction(_ sender: Any?) {
        nonisolated(unsafe) let sender = sender
        MainActor.assumeIsolated {
            let item = (sender as? [String: Any])?[kIMKCommandMenuItemName] as? NSMenuItem ?? sender as? NSMenuItem
            guard let item else { return }
            AppEnvironment.shared.inputMenu.perform(item)
        }
    }
}
