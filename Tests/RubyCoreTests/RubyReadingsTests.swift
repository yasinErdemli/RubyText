import RubyCore
import Testing

@Suite struct RubyReadingsTests {
    @Test(arguments: [
        ("ビール", "びーる"), ("コーヒー", "こーひー"), ("エーアイ", "えーあい"),
        ("ヴァイオリン", "ゔぁいおりん"), ("いすゞ", "いすゞ"), ("ヽヾ", "ゝゞ"),
        ("ｶﾞｯｺｳ", "がっこう"), ("ﾋﾞｰﾙ2本", "びーる2本"), ("3ヶ月", "3ヶ月"), ("漢字", "漢字"),
    ])
    func hiragana(_ text: String, _ expected: String) {
        #expect(RubyReadings.hiragana(text) == expected)
    }

    /// Furigana from markup, as base:reading pairs.
    private func furigana(_ markup: String) -> [String] {
        let content = RubyContent.content(for: markup)
        let utf16 = Array(content.string.utf16)
        return content.words.flatMap(\.furigana).map {
            String(decoding: utf16[$0.range], as: UTF16.self) + ":" + $0.text
        }
    }

    @Test func manualReadingsShowAsWritten() {
        #expect(furigana("{ＡＩ|エーアイ}") == ["ＡＩ:エーアイ"])
        #expect(furigana("{本気|マジ}で") == ["本気:マジ"])
        #expect(furigana("{生|ナマ}ビール") == ["生:ナマ"])
    }

    @Test func dictionaryReadingsKeepLongVowels() {
        #expect(furigana("生ビール") == ["生:なま"])
    }
}
