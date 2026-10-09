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
}
