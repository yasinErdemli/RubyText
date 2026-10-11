// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
import RubyCore
import Testing

@Suite struct RubyPhraseReadingsTests {
    @Test(arguments: [
        // なに shortens to なん before だ, で, の, と, て, な and じゃ.
        ("これは何ですか。", "なん"), ("何だ、これは。", "なん"), ("何の話？", "なん"),
        ("何と言った？", "なん"), ("何て言ったの？", "なん"), ("何でも食べる。", "なん"),
        ("何なの？", "なん"), ("何じゃこりゃ。", "なん"), ("何という本？", "なん"),
        // It stays なに elsewhere.
        ("何を食べますか。", "なに"), ("何が好き？", "なに"), ("何も言わない。", "なに"),
        ("何か飲む？", "なに"), ("何に使う？", "なに"), ("何から始める？", "なに"),
    ])
    func nan(_ sentence: String, _ expected: String) {
        #expect(reading(of: "何", in: sentence) == expected)
    }

    @Test func countersKeepTheirReading() {
        #expect(reading(of: "何人", in: "何人いる？") == "なんにん")
        #expect(reading(of: "何時", in: "何時に会う？") == "なんじ")
    }

    @Test(arguments: [
        ("日本に住んでいる。", "日本", "にほん"), ("日本人の友達", "日本人", "にほんじん"),
        ("日本中で話題になった。", "日本中", "にほんじゅう"), ("日本語を話す。", "日本語", "にほんご"),
        // Names that are read にっぽん.
        ("日本銀行が発表した。", "日本銀行", "にっぽんぎんこう"),
        // Readings you give always win.
        ("{日本|にっぽん}の空", "日本", "にっぽん"),
    ])
    func nihon(_ sentence: String, _ word: String, _ expected: String) {
        #expect(reading(of: word, in: sentence) == expected)
    }
}
#endif
