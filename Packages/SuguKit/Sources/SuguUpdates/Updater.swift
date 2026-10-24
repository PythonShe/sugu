import Foundation
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
    private var controller: SPUStandardUpdaterController?
    /// A scheduled check found an update the user has not seen yet.
    public private(set) var hasPendingUpdate = false

    override public init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        controller?.updater.httpHeaders = ["Accept-Language": "*"]
    }

    public var isAvailable: Bool { controller != nil }

    public var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
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
