import Foundation

/// Evaluates a numeric field's text as a chain of `*`/`/` operations (e.g. "1920*2", "3840/2"),
/// left to right, so typing an expression into any numeric field lands on the computed value. A
/// plain number (no operator) evaluates to itself, so this is a drop-in replacement for
/// `Double(text)` wherever a field's text is parsed.
enum ArithmeticExpression {
    static func evaluate(_ text: String) -> Double? {
        var numberText = ""
        var result: Double?
        var pendingOperator: Character?
        func flush() -> Bool {
            guard let value = Double(numberText.trimmingCharacters(in: .whitespaces)) else { return false }
            numberText = ""
            guard let op = pendingOperator, let current = result else {
                result = value
                return true
            }
            guard op != "/" || value != 0 else { return false }
            result = op == "*" ? current * value : current / value
            return true
        }
        for character in text {
            if character == "*" || character == "/" {
                guard flush() else { return nil }
                pendingOperator = character
            } else {
                numberText.append(character)
            }
        }
        guard flush(), let result, result.isFinite else { return nil }
        return result
    }

    /// `evaluate(_:)`, but only if the result is a whole number (e.g. a pixel count): "5/2" is
    /// rejected exactly as a plain "2.5" would be, rather than rounding it to something the caller
    /// never actually typed.
    static func evaluateWholeNumber(_ text: String) -> Int? {
        guard let value = evaluate(text), value == value.rounded() else { return nil }
        return Int(exactly: value)
    }
}

/// A floating-point field (`Double`, `CGFloat`, ...) that also accepts `*`/`/` expressions; see
/// `ArithmeticExpression`. Generic so it drops into any numeric `TextField` regardless of which
/// floating-point type that field's state happens to use.
struct ArithmeticFloatFormatStyle<Value: BinaryFloatingPoint>: ParseableFormatStyle {
    typealias FormatInput = Value
    typealias FormatOutput = String
    var fractionLength: ClosedRange<Int> = 0...0
    func format(_ value: Value) -> String {
        Double(value).formatted(.number.precision(.fractionLength(fractionLength)))
    }
    var parseStrategy: ArithmeticFloatParseStrategy<Value> { ArithmeticFloatParseStrategy() }
}

struct ArithmeticFloatParseStrategy<Value: BinaryFloatingPoint>: ParseStrategy {
    typealias ParseInput = String
    typealias ParseOutput = Value
    func parse(_ value: String) throws -> Value {
        guard let result = ArithmeticExpression.evaluate(value) else { throw CocoaError(.formatting) }
        return Value(result)
    }
}

/// An `Int` field that also accepts a `*`/`/` expression whose result is a whole number (e.g.
/// "500/2"); a non-whole result like "5/2" is rejected exactly as a plain "2.5" would be. See
/// `ArithmeticExpression`.
struct ArithmeticIntFormatStyle: ParseableFormatStyle {
    typealias FormatInput = Int
    typealias FormatOutput = String
    func format(_ value: Int) -> String { String(value) }
    var parseStrategy: ArithmeticIntParseStrategy { ArithmeticIntParseStrategy() }
}

struct ArithmeticIntParseStrategy: ParseStrategy {
    typealias ParseInput = String
    typealias ParseOutput = Int
    func parse(_ value: String) throws -> Int {
        guard let n = ArithmeticExpression.evaluateWholeNumber(value) else { throw CocoaError(.formatting) }
        return n
    }
}
