import RubyTransliteration
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
        let phrase = RubyPhrase([.init(reading, pronunciation: pronunciation)], following: next)
        #expect(RubyRomanization.hepburn.transliterate(phrase) == expected)
    }

    /// Text written in kana, with no dictionary to say what's a word.
    @Test(arguments: [
        // Repeat marks and stretched vowels.
        ("いすゞ", "isuzu"),
        ("こゝろ", "kokoro"),
        ("ねぇ", "nē"),
        ("すごーい", "sugōi"),
        ("ｶﾞｯｺｳ", "gakkō"),
        // Punctuation, and words joined by a middle dot.
        ("はい、そうです。", "hai, sōdesu."),
        ("「はい」といった。", "“hai” toitta."),
        ("ほんとう？うん！", "hontō? un!"),
        ("あっ。", "a."),
        ("ジョン・スミス", "jon sumisu"),
        // Full-width Latin becomes ASCII; kanji stay as they are.
        ("ＡＩ", "AI"),
        ("漢じ", "漢ji"),
    ])
    func kana(_ text: String, _ expected: String) {
        #expect(RubyRomanization.hepburn.transliterate(text) == expected)
    }

    @Test func pronunciationDecidesLongVowelsAndParticles() {
        #expect(RubyRomanization.hepburn.transliterate("おもう") == "omō")
        #expect(RubyRomanization.hepburn.transliterate("おもう", pronunciation: "おもう") == "omou")
        #expect(RubyRomanization.hepburn.transliterate("きょうは", pronunciation: "きょーわ") == "kyōwa")
    }

    /// Kana where the systems differ, as Hepburn, Nihon-shiki, and passport
    /// style write them.
    @Test(arguments: [
        ("きょうと", "kyōto", "kyôto", "kyoto"),
        ("さとう", "satō", "satô", "sato"),
        ("おおの", "ōno", "ôno", "ono"),
        ("コーヒー", "kōhī", "kôhî", "kohi"),
        ("けいたい", "keitai", "keitai", "keitai"),
        ("ふじさん", "fujisan", "huzisan", "fujisan"),
        ("しんぶん", "shinbun", "sinbun", "shimbun"),
        ("ほんま", "honma", "honma", "homma"),
        ("なんば", "nanba", "nanba", "namba"),
        ("てんぷら", "tenpura", "tenpura", "tempura"),
        ("げんいん", "gen'in", "gen'in", "genin"),
        ("まっちゃ", "matcha", "mattya", "matcha"),
        ("ちゃ じゃ しゅ", "cha ja shu", "tya zya syu", "cha ja shu"),
        ("つづく", "tsuzuku", "tuduku", "tsuzuku"),
        ("はなぢ", "hanaji", "hanadi", "hanaji"),
        ("を", "o", "wo", "o"),
        ("ファイル", "fairu", "hwairu", "fairu"),
        ("シェフ", "shefu", "syehu", "shefu"),
        ("ヴァイオリン", "vaiorin", "vaiorin", "baiorin"),
    ])
    func systems(_ kana: String, _ hepburn: String, _ nippon: String, _ passport: String) {
        #expect(RubyRomanization.hepburn.transliterate(kana) == hepburn)
        #expect(RubyRomanization.nippon.transliterate(kana) == nippon)
        #expect(RubyRomanization.passport.transliterate(kana) == passport)
    }
}
