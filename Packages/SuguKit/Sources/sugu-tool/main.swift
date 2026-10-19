import Foundation

// sugu-tool: build-time and diagnostic commands. Never touches the
// installed input method or the user's input sources.
let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
usage: sugu-tool build-data --wanxiang <dir> --opencc <dir> --out <dir> [--version <v>]
       sugu-tool convert --data <dir> (--chinese | --japanese) <reading>...
"""

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

do {
    switch arguments.first {
    case "build-data":
        guard let wanxiang = option("--wanxiang"), let openCC = option("--opencc"), let out = option("--out") else { fail(usage) }
        try await BuildData.run(
            wanxiang: URL(fileURLWithPath: wanxiang),
            openCC: URL(fileURLWithPath: openCC),
            output: URL(fileURLWithPath: out),
            version: option("--version") ?? "dev"
        )
    case "convert":
        guard let data = option("--data") else { fail(usage) }
        let readings = arguments.dropFirst().filter { !$0.hasPrefix("--") && $0 != data }
        try await Convert.run(data: URL(fileURLWithPath: data), japanese: arguments.contains("--japanese"), readings: Array(readings))
    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
