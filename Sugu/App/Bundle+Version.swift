import Foundation

extension Bundle {
    /// The marketing version, such as 0.1.0.
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    /// The build number.
    var buildVersion: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
}
