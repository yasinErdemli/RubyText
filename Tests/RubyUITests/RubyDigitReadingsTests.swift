import RubyCore
@testable import RubyUI
import Testing

@Suite struct RubyDigitReadingsTests {
    @Test(arguments: ["2026年", "3日", "３日", "3.5", "10分"])
    func digitNumbers(_ text: String) {
        #expect(RubyText.isDigitNumber(text))
    }

    @Test(arguments: ["三日", "二〇二六年", "漢字", "ＡＩ", "iPhone15", ""])
    func otherText(_ text: String) {
        #expect(!RubyText.isDigitNumber(text))
    }
}
