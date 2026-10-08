@testable import RubyCore
import Testing

@Suite struct RubyRomajiTests {
    @Test(arguments: [
        // Plain and combined kana.
        ("ねこ", nil, nil, "neko"),
        ("きょうと", nil, nil, "kyōto"),
        ("しゃしん", nil, nil, "shashin"),
        ("ちゃ", nil, nil, "cha"),
        ("じゅう", nil, nil, "jū"),
        ("ふぁいる", nil, nil, "fairu"),
        ("てぃっしゅ", nil, nil, "tisshu"),
        ("ウィキ", nil, nil, "wiki"),
        ("ヴァイオリン", nil, nil, "vaiorin"),
        ("ちぇっく", nil, nil, "chekku"),
        // っ doubles the next consonant, also across words.
        ("まっちゃ", nil, nil, "matcha"),
        ("いっ", nil, "た", "it"),
        ("あっ", nil, nil, "a"),
        // ん before a vowel or y.
        ("げんいん", nil, nil, "gen'in"),
        ("きんようび", "きんよーび", nil, "kin'yōbi"),
        ("しんぶん", nil, nil, "shinbun"),
        ("ごはん", nil, "を", "gohan"),
        // Long vowels: ー, and the pronunciation where there is one.
        ("こーひー", nil, nil, "kōhī"),
        ("とうきょう", "とーきょー", nil, "tōkyō"),
        ("せんせい", "せんせー", nil, "sensei"),
        ("おもう", "おもう", nil, "omou"),
        ("みずうみ", "みずうみ", nil, "mizuumi"),
        ("おおきい", "おーきい", nil, "ōkii"),
        ("いい", nil, nil, "ii"),
        // Particles take their pronunciation.
        ("は", "わ", nil, "wa"),
        ("へ", "え", nil, "e"),
        ("を", nil, nil, "o"),
        ("こんにちは", "こんにちわ", nil, "konnichiwa"),
    ] as [(String, String?, String?, String)])
    func hepburn(_ reading: String, _ pronunciation: String?, _ next: String?, _ expected: String) {
        #expect(RubyRomaji.hepburn(reading, pronunciation: pronunciation, next: next) == expected)
    }

    /// Romaji words for whole sentences, as shown below the text.
    @Test(arguments: [
        ("今日は東京へ行きたい。", "kyō wa tōkyō e ikitai"),
        ("コーヒーを飲みながら日本語を勉強しています。", "kōhī o nominagara nihongo o benkyō shite imasu"),
        ("漫画を読んだ。", "manga o yonda"),
        ("気に入った店", "kiniitta mise"),
        ("東京で会おう。", "tōkyō de aō"),
        ("学校では静かだ。", "gakkō dewa shizuka da"),
        ("映画でも見ましょう。", "eiga demo mimashō"),
        ("食べてしまった。", "tabete shimatta"),
        ("先生です。", "sensei desu"),
        ("吾輩は猫である。", "wagahai wa neko de aru"),
        ("湖を追う。", "mizuumi o ou"),
    ])
    func romajiWords(_ text: String, _ expected: String) {
        let content = RubyContent.content(for: text)
        #expect(content.romajiWords.map(\.text).joined(separator: " ") == expected)
    }

    @Test(arguments: [
        ("十日", "tōka"),
        ("2026年", "nisen nijūrokunen"),
        ("3500円", "sanzen gohyakuen"),
        ("六百人", "roppyakunin"),
        ("1,234,567", "hyaku nijūsanman yonsen gohyaku rokujūnana"),
        ("100", "hyaku"),
    ])
    func numbersReadInParts(_ text: String, _ expected: String) {
        let content = RubyContent.content(for: text)
        let romaji = content.romajiWords.map(\.text).joined(separator: " ")
        #expect(romaji == expected, "\(romaji)")
    }
}
