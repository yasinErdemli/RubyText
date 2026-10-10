import RubyCore
import Testing

@Suite struct RubyReadingsTests {
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

    /// Readings you give that the analyzer agrees with are spoken as it
    /// says: the う of 思う isn't a long vowel.
    @Test func manualReadingsArePronouncedAsTheAnalyzerSays() {
        func romaji(_ markup: String) -> [String?] {
            RubyContent.content(for: markup).words.map(\.romaji)
        }
        #expect(romaji("{思う|おもう}") == ["omou"])
        #expect(romaji("{追う|おう}") == ["ou"])
        #expect(romaji("{東京|とうきょう}") == ["Tōkyō"])
        // A reading the analyzer doesn't give is read as written.
        #expect(romaji("{宇宙|そら}") == ["sora"])
        #expect(romaji("{東京|トーキョー}") == ["tōkyō"])
    }
}
