import Foundation
import RubyCore
import Testing

/// Readings given in code with string interpolation.
@Suite struct RubyStringTests {
    private func content(_ string: RubyString) -> RubyContent {
        RubyContent.content(for: string, analyzer: RubyMeCabAnalyzer.ipadic)
    }

    /// Each word with furigana, as its text and readings.
    private func furigana(_ content: RubyContent) -> [String] {
        content.words.filter { !$0.furigana.isEmpty }.map { word in
            RubyReadingUnits.substring(of: content.string, utf16Range: word.range) + ":" + word.furigana.map(\.text).joined(separator: ",")
        }
    }

    @Test func piecesMakeOneText() {
        let string: RubyString = "\("今日", reading: "きょう")は{明日|あした}も\(verbatim: "iPhone")で\(3)回"
        #expect(string.plainText == "今日は明日もiPhoneで3回")
        #expect(content(string).string == "今日は明日もiPhoneで3回")
    }

    @Test func givenReadingsWin() {
        let words = content("\("今日", reading: "こんにち")は晴れ").words
        #expect(words.first?.furigana.map(\.text) == ["こんにち"])
        #expect(words.first?.source == .manual)
    }

    @Test func missingReadingsAreAnalyzed() {
        let reading: String? = nil
        #expect(furigana(content("\("東京", reading: reading)へ行く")) == ["東京:とうきょう", "行く:い"])
    }

    @Test func piecesAreAnalyzedTogether() {
        // 勉 and 強 come from different pieces, but are read as one word.
        #expect(furigana(content("\("勉")強した")) == ["勉強:べんきょう"])
        // A number reads with the counter after it.
        #expect(furigana(content("\(3)日に行く。")).first == "3日:みっか")
    }

    @Test func interpolatedTextIsNotMarkup() {
        let input = "{悪|わる}い"
        let content = content("\(input)")
        #expect(content.string == "{悪|わる}い")
        #expect(!content.words.contains { $0.source == .manual })
    }

    @Test func verbatimTextIsNotAnnotated() {
        let content = content("\(verbatim: "東京")へ行く")
        #expect(furigana(content) == ["行く:い"])
        #expect(!content.words.contains { $0.range.overlaps(0..<2) })
        #expect(content.romajiWords.map(\.text) == ["e", "iku"])
    }

    @Test func verbatimTextIsNotAskedAbout() {
        #expect(RubyModelReadings.questions(in: "夜の公園は人気がない。" as RubyString, analyzer: RubyMeCabAnalyzer.ipadic).count == 1)
        #expect(RubyModelReadings.questions(in: "夜の公園は\(verbatim: "人気")がない。", analyzer: RubyMeCabAnalyzer.ipadic).isEmpty)
    }

    @Test func namesReadWithTheirPhoneticNames() throws {
        var name = PersonNameComponents()
        name.familyName = "田中"
        name.givenName = "花子"
        var phonetic = PersonNameComponents()
        phonetic.familyName = "タナカ"
        phonetic.givenName = "ハナコ"
        name.phoneticRepresentation = phonetic

        let hiragana = content("\(name)さんと話した。")
        #expect(hiragana.string == "田中花子さんと話した。")
        #expect(furigana(hiragana).prefix(2) == ["田中:たなか", "花子:はなこ"])
        let katakana = content("\(name.rubyString(readings: .katakana))さん")
        #expect(furigana(katakana) == ["田中:タナカ", "花子:ハナコ"])
    }

    @Test func otherNamesReadAsFormatted() {
        var name = PersonNameComponents()
        name.givenName = "John"
        name.familyName = "Smith"
        let text = name.rubyString.plainText
        #expect(text.contains("John") && text.contains("Smith"))
    }

    @Test func conformingTypes() {
        struct City: RubyStringConvertible {
            var name = "札幌"
            var kana: String? = "さっぽろ"
            var rubyString: RubyString { "\(name, reading: kana)市" }
        }
        #expect(furigana(content("\(City())に住む")).first == "札幌:さっぽろ")
    }

    @Test func converting() {
        let converter = RubyConverter(analyzer: RubyMeCabAnalyzer.ipadic)
        #expect(converter.convert("\("本気", reading: "マジ")で\(verbatim: "AI")を使う" as RubyString, to: .hiragana) == "マジでAIをつかう")
        #expect(converter.annotate("\("宇宙", reading: "そら")を見る" as RubyString, with: .hiragana) == "宇宙（そら）を見（み）る")
    }

    @Test func concatenating() {
        var string: RubyString = "\("今日", reading: "きょう")"
        string += "は晴れ"
        #expect((string + "。").plainText == "今日は晴れ。")
        #expect(RubyString(markup: "{今日|きょう}") == "{今日|きょう}")
    }
}
