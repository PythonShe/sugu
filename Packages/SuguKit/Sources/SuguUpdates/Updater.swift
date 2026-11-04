import AppKit
import os
import Sparkle

/// Update checks through Sparkle. Off in builds without an update signing
/// key (development builds), so they never offer someone else's release.
/// No system profile is sent (Info.plist, and the delegate below), and no
/// preferred languages: requests name only Sugu's and Sparkle's versions.
///
/// Sugu runs in the background, so an update found by a scheduled check
/// is not put in front of the app being typed in: it waits as
/// `hasPendingUpdate` until the user asks for it.
@MainActor
public final class Updater: NSObject, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    private var updater: SPUUpdater?
    /// A scheduled check found an update the user has not seen yet.
    public private(set) var hasPendingUpdate = false

    override public init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        let driver = UpdatePromptDriver(hostBundle: .main, delegate: self)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        updater.httpHeaders = ["Accept-Language": "*"]
        do {
            try updater.start()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sugu", category: "updates")
                .error("The updater did not start: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.updater = updater
    }

    public var isAvailable: Bool { updater != nil }

    public var checksAutomatically: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    public func checkForUpdates() {
        updater?.checkForUpdates()
    }

    nonisolated public func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    // MARK: Gentle reminders

    public var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Never shown by itself: "immediate focus" means Sugu was just
    /// launched or the Mac was idle, not that Sugu has the focus, and the
    /// window would open over the app being typed in.
    public func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    public func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { hasPendingUpdate = true }
    }

    public func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        hasPendingUpdate = false
    }

    public func standardUserDriverWillFinishUpdateSession() {
        hasPendingUpdate = false
    }
}

/// Sparkle only bounces a Dock icon when an update is ready to install, and
/// Sugu has none, so the prompt opens behind the app being typed in and is
/// easily never seen. It comes forward without taking the keyboard: a Return
/// typed at that moment must not install the update and quit the input method.
private final class UpdatePromptDriver: SPUStandardUserDriver {
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showReady(toInstallAndRelaunch: reply)
        let sparkle = Bundle(for: SPUUpdater.self)
        for window in NSApp.windows where window.isVisible {
            guard let controller = window.windowController, Bundle(for: type(of: controller)) == sparkle else { continue }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.orderFrontRegardless()
        }
    }
}
