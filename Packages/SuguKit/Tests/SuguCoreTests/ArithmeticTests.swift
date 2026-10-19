import Testing
@testable import SuguCore

struct ArithmeticTests {
    @Test func precedence() {
        #expect(Arithmetic.evaluate("1+2*3") == 7)
        #expect(Arithmetic.evaluate("(1+2)*3") == 9)
        #expect(Arithmetic.evaluate("2^3^2") == 512)
        #expect(Arithmetic.evaluate("-3+5") == 2)
    }

    @Test func fullWidthAndSymbols() {
        #expect(Arithmetic.evaluate("１２×３") == 36)
        #expect(Arithmetic.evaluate("9÷4") == 2.25)
    }

    @Test func rejectsNonExpressions() {
        #expect(Arithmetic.evaluate("123") == nil)
        #expect(Arithmetic.evaluate("1/0") == nil)
        #expect(Arithmetic.evaluate("1+") == nil)
        #expect(Arithmetic.evaluate("a+1") == nil)
    }

    @Test func formatting() {
        #expect(Arithmetic.format(7) == "7")
        #expect(Arithmetic.format(2.25) == "2.25")
        #expect(Arithmetic.format(1.0 / 3.0) == "0.3333333333")
    }
}
