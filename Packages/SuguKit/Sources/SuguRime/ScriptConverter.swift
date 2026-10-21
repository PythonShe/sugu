import CRimeShim
import Foundation
import SuguCore

/// Converts Chinese text between scripts with the OpenCC tables librime's
/// filters use, for text that does not come out of librime: learned words,
/// computed candidates, and Chinese forms of Japanese names.
public final class ScriptConverter {
    private var handles: [UnsafeMutableRawPointer] = []

    /// A chain of OpenCC configurations applied in order; nil when one does
    /// not load.
    public init?(configurations: [URL]) {
        for url in configurations {
            // deinit closes the handles already open.
            guard let handle = opencc_open(url.path), Int(bitPattern: handle) != -1 else { return nil }
            handles.append(handle)
        }
    }

    deinit {
        handles.forEach { _ = opencc_close($0) }
    }

    public func convert(_ text: String) -> String {
        handles.reduce(text) { text, handle in
            text.withCString { input in
                guard let output = opencc_convert_utf8(handle, input, strlen(input)) else { return text }
                defer { opencc_convert_utf8_free(output) }
                return String(cString: output)
            }
        }
    }

    /// Text in any script (Simplified, Traditional or Japanese forms) to
    /// `script`, through Simplified.
    public static func toScript(_ script: ChineseScript, openCC directory: URL) -> ScriptConverter? {
        var names = ["jp2t.json", "t2s.json"]
        if let option = RimeSchema.option(for: script),
           let config = RimeSchema.scriptFilters.first(where: { $0.option == option })?.config {
            names.append(config)
        }
        return ScriptConverter(configurations: names.map { directory.appendingPathComponent($0) })
    }
}
