import RubyTransliteration
import Testing

@Suite struct RubyKanaTests {
    @Test(arguments: [
        ("ビール", "びーる"), ("コーヒー", "こーひー"), ("エーアイ", "えーあい"),
        ("ヴァイオリン", "ゔぁいおりん"), ("いすゞ", "いすゞ"), ("ヽヾ", "ゝゞ"),
        ("ｶﾞｯｺｳ", "がっこう"), ("ﾋﾞｰﾙ2本", "びーる2本"), ("3ヶ月", "3ヶ月"), ("漢字", "漢字"),
    ])
    func hiragana(_ text: String, _ expected: String) {
        #expect(RubyKana.hiragana(text) == expected)
    }

    @Test(arguments: [
        ("とうきょう", "トウキョウ"), ("こーひー", "コーヒー"), ("ゝゞ", "ヽヾ"),
        ("ｶﾞｯｺｳ", "ガッコウ"), ("ﾊﾟﾝ", "パン"), ("漢字とカナ", "漢字トカナ"),
    ])
    func katakana(_ text: String, _ expected: String) {
        #expect(RubyKana.katakana(text) == expected)
    }

    @Test func halfWidthPunctuationWidens() {
        #expect(RubyKana.hiragana("ｶﾞｯｺｳ｡") == "がっこう。")
    }

    @Test func charactersAreClassified() {
        #expect("漢々ヶ".allSatisfy(RubyKana.isKanji))
        #expect(!RubyKana.isKanji("あ"))
        #expect("あゝゞ".allSatisfy(RubyKana.isHiragana))
        #expect(!RubyKana.isHiragana("ア"))
        #expect("アーヽｱ".allSatisfy(RubyKana.isKatakana))
        #expect(!RubyKana.isKatakana("・"))
        #expect("あア".allSatisfy(RubyKana.isKana))
        #expect(!RubyKana.isKana("漢"))
        #expect("漢あア".allSatisfy(RubyKana.isJapanese))
        #expect(!"a1。".contains(where: RubyKana.isJapanese))
    }
}
