import Darwin
import Foundation

struct LanguageResult: Codable {
    var keystrokes: [Double] = []
    var conversions: [Double] = []
    var cases = 0
    var topOne = 0
    var inFirstPage = 0
    var characters = 0
    var characterErrors = 0
    var keysTyped = 0
    var failures: [String] = []

    mutating func record(expected: String, output: String, inPage: Bool, keys: Int) {
        cases += 1
        characters += expected.count
        keysTyped += keys
        characterErrors += editDistance(Array(expected), Array(output))
        if output == expected { topOne += 1 } else { failures.append("\(expected) → \(output)") }
        if inPage { inFirstPage += 1 }
    }

    var topOneRate: Double { cases == 0 ? 0 : Double(topOne) / Double(cases) }
    var firstPageRate: Double { cases == 0 ? 0 : Double(inFirstPage) / Double(cases) }
    var characterAccuracy: Double { characters == 0 ? 0 : 1 - Double(characterErrors) / Double(characters) }
    var keysPerCharacter: Double { characters == 0 ? 0 : Double(keysTyped) / Double(characters) }
}

struct Memory: Codable {
    var footprintMB: Double
    var residentMB: Double

    static func current() -> Memory {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return Memory(footprintMB: 0, residentMB: 0) }
        return Memory(footprintMB: Double(info.phys_footprint) / 1_048_576, residentMB: Double(info.resident_size) / 1_048_576)
    }
}

struct Report: Codable {
    /// Budgets from AGENTS.md: keystroke to updated candidates < 5 ms p99,
    /// resident memory < 200 MB in the default configuration.
    static let keystrokeBudget = 5.0
    static let memoryBudget = 200.0

    var chinese = LanguageResult()
    var japanese = LanguageResult()
    var memory = Memory(footprintMB: 0, residentMB: 0)

    var keystrokeP99: Double { percentile(chinese.keystrokes + japanese.keystrokes, 0.99) }

    var withinBudgets: Bool {
        keystrokeP99 < Self.keystrokeBudget && memory.footprintMB < Self.memoryBudget
    }

    var summary: String {
        func line(_ name: String, _ result: LanguageResult) -> String {
            let accuracy = String(format: "top-1 %.0f%%  first page %.0f%%  characters %.1f%%  keys/char %.2f",
                                  result.topOneRate * 100, result.firstPageRate * 100, result.characterAccuracy * 100, result.keysPerCharacter)
            let latency = String(format: "keystroke p50 %.2f ms  p99 %.2f ms  max %.2f ms",
                                 percentile(result.keystrokes, 0.5), percentile(result.keystrokes, 0.99), result.keystrokes.max() ?? 0)
            var text = "\(name) (\(result.cases) sentences, \(result.keystrokes.count) keystrokes)\n  \(accuracy)\n  \(latency)"
            if !result.conversions.isEmpty {
                text += String(format: "\n  conversion p50 %.2f ms  p99 %.2f ms", percentile(result.conversions, 0.5), percentile(result.conversions, 0.99))
            }
            if !result.failures.isEmpty {
                text += "\n  misses:\n" + result.failures.map { "    \($0)" }.joined(separator: "\n")
            }
            return text
        }
        return [
            line("Chinese", chinese),
            line("Japanese", japanese),
            String(format: "Memory: footprint %.0f MB, resident %.0f MB", memory.footprintMB, memory.residentMB),
            String(format: "Budgets: keystroke p99 %.2f ms (< %.0f), footprint %.0f MB (< %.0f) — %@",
                   keystrokeP99, Self.keystrokeBudget, memory.footprintMB, Self.memoryBudget, withinBudgets ? "pass" : "FAIL"),
        ].joined(separator: "\n")
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
}

func editDistance(_ a: [Character], _ b: [Character]) -> Int {
    guard !a.isEmpty else { return b.count }
    guard !b.isEmpty else { return a.count }
    var previous = Array(0...b.count)
    for (i, x) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, y) in b.enumerated() {
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
        }
        previous = current
    }
    return previous[b.count]
}
