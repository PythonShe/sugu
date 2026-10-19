import Foundation

/// Evaluates simple arithmetic typed as a reading: + - * / × ÷ ^ % and
/// parentheses over decimals.
public enum Arithmetic {
    /// Returns nil unless the input is an expression with at least one
    /// operator that evaluates to a finite number.
    public static func evaluate(_ input: String) -> Double? {
        let normalized = WidthConversion.halfWidth(input)
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "ー", with: "-")
            .replacingOccurrences(of: " ", with: "")
        guard normalized.contains(where: { "+-*/^%".contains($0) }),
              normalized.contains(where: \.isASCIIDigitCharacter),
              normalized.allSatisfy({ $0.isASCIIDigitCharacter || "+-*/^%().".contains($0) }) else { return nil }
        var parser = Parser(Array(normalized))
        guard let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// Formats a result without a trailing ".0" and with at most 10 decimals.
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }
        var isAtEnd: Bool { index == chars.count }

        mutating func peek() -> Character? { index < chars.count ? chars[index] : nil }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                index += 1
                guard let rhs = power() else { return nil }
                switch op {
                case "*": value *= rhs
                case "/": guard rhs != 0 else { return nil }; value /= rhs
                default: guard rhs != 0 else { return nil }; value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exponent = power() else { return nil }
                return Foundation.pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if peek() == "-" {
                index += 1
                return unary().map { -$0 }
            }
            return primary()
        }

        mutating func primary() -> Double? {
            if peek() == "(" {
                index += 1
                let value = expression()
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let c = peek(), c.isASCIIDigitCharacter || c == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}
