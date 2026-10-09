import RubyCore
import Testing

/// What voices say in place of the text, in each way it can be written.
@Suite struct RubySpeechTests {
    /// Each spoken stretch, as the text it covers and what's said for it.
    private func speech(_ content: RubyContent, _ readings: RubySpokenReadings = .corrections) -> [String: String] {
        Dictionary(uniqueKeysWithValues: content.speech(readings).map {
            (RubyReadingUnits.substring(of: content.string, utf16Range: $0.range), $0.text)
        })
    }

    @Test func manualReadingsAreSpoken() {
        let content = RubyContent.content(for: "{宇宙|そら}を見上げた")
        // The voice reads dictionary words itself.
        #expect(speech(content) == ["宇宙": "そら"])
        #expect(speech(content, .all) == ["宇宙": "そら", "見上げ": "みあげ"])
        #expect(speech(content, .dictionary) == ["見上げ": "みあげ"])
        #expect(speech(content, []).isEmpty)
    }

    @Test func ruleReadingsAreSpoken() {
        let content = RubyContent.content(for: "3日に行く。")
        #expect(speech(content) == ["3日": "みっか"])
        #expect(speech(content, .manual).isEmpty)
    }

    @Test func kanaTextIsReadAsWritten() {
        let content = RubyContent.content(for: "{宇宙|そら}を見上げた").transcribed(to: .hiragana)
        #expect(content.speech(.all).isEmpty)
    }

    @Test func romajiTextIsSpokenInKana() {
        let content = RubyContent.content(for: "今日は東京へ行きたい。").transcribed(to: .romaji)
        // Every word, whatever the readings, as kana text would say it.
        let expected = ["kyō": "きょう", "wa": "は", "tōkyō": "とうきょう", "e": "へ", "iki": "いき", "tai": "たい"]
        #expect(speech(content, []) == expected)
        #expect(speech(content) == expected)
    }

    @Test func inlineReadingsAreSpokenOnce() {
        let content = RubyContent.content(for: "{宇宙|そら}を見た").withInlineReadings(in: .hiragana)
        #expect(content.string == "宇宙（そら）を見（み）た")
        // As written, unless the reading is one voices say.
        #expect(speech(content) == ["宇宙（そら）": "そら", "見（み）": "見"])
        #expect(speech(content, .all) == ["宇宙（そら）": "そら", "見（み）": "み"])
    }

    @Test func spokenStringMapsBack() {
        let content = RubyContent.content(for: "{日本|にっぽん}の空")
        let spoken = content.spokenString(.corrections)
        #expect(spoken.string == "にっぽんの空")
        // Anywhere in the reading is the start of its word.
        #expect((0...4).map(spoken.sourceOffset) == [0, 0, 0, 0, 2])
        #expect(spoken.sourceOffset(5) == 3)
        #expect(content.spokenString([]).string == "日本の空")
    }

    @Test func ssmlIsEscaped() {
        #expect(RubySpokenText(range: 0..<1, text: "a<b>&c").ssml == "a&lt;b&gt;&amp;c")
    }

    @Test func wordInfoSource() {
        let content = RubyContent.content(for: "{宇宙|そら}を3日見た")
        let info = { (offset: Int) in
            RubyWordInfo.info(for: content.dictionaryWords.first { $0.contains(offset) }!, in: content)
        }
        #expect(info(0).source == .manual)
        #expect(info(3).source == .rule)
        #expect(info(5).source == .dictionary)
    }
}
