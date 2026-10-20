import Foundation
import Sparkle

/// Update checks through Sparkle. Off in builds without an update signing
/// key (development builds), so they never offer someone else's release.
/// No system profile is sent (Info.plist, and the delegate below).
@MainActor
public final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    override public init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    public var isAvailable: Bool { controller != nil }

    public var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    nonisolated public func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String] { [] }
}
