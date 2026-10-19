import Foundation
import SuguInput

/// Where Sugu keeps its files. Bundled data is read-only; everything Sugu
/// writes lives under Application Support.
struct AppLocations {
    let support: URL
    let bundledRime: URL
    let bundledLexicon: URL

    static let current: AppLocations = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return AppLocations(
            support: base.appendingPathComponent("Sugu", isDirectory: true),
            bundledRime: resources.appendingPathComponent("Rime", isDirectory: true),
            bundledLexicon: resources.appendingPathComponent("Lexicon", isDirectory: true)
        )
    }()

    var learnedStore: URL {
        support.appendingPathComponent("Learning", isDirectory: true).appendingPathComponent("learned.sqlite")
    }

    var engines: EngineHub.Locations {
        EngineHub.Locations(
            rimeShared: bundledRime,
            rimeUser: support.appendingPathComponent("Rime", isDirectory: true),
            azooKey: support.appendingPathComponent("AzooKey", isDirectory: true),
            models: support.appendingPathComponent("Models", isDirectory: true)
        )
    }
}
