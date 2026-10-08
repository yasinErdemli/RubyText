import RubyCore
@testable import RubyUI
import Testing

@Suite struct RubyFuriganaFilterTests {
    @Test func showsDigitReadingsByDefault() {
        #expect(RubyFuriganaFilter.all.showsReading(over: "2026年"))
        #expect(RubyFuriganaFilter.all.showsReading(over: "3日"))
    }

    @Test func hidesReadingsOverDigits() {
        let filter = RubyFuriganaFilter.all.hidingDigits()
        #expect(!filter.showsReading(over: "2026年"))
        #expect(!filter.showsReading(over: "３日"))
        #expect(!filter.showsReading(over: "3.5"))
        // Kanji numerals and other words keep their readings.
        #expect(filter.showsReading(over: "三日"))
        #expect(filter.showsReading(over: "漢字"))
    }

    @Test func combinesWithLevels() {
        let filter = RubyFuriganaFilter.above(.n1).hidingDigits()
        #expect(!filter.showsReading(over: "3日"))
        #expect(filter.showsReading(over: "ＡＩ"))
    }
}
