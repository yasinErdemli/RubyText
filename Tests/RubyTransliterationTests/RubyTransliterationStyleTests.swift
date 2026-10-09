import RubyTransliteration
import Testing

@Suite struct RubyTransliterationStyleTests {
    @Test(arguments: RubyRomanization.allCases)
    func builtInStylesWriteEverything(_ romanization: RubyRomanization) {
        #expect(RubyTransliterationValidator.validate(romanization.style) == [])
    }

    @Test func validatorFindsMissingSyllables() {
        var style = RubyTableStyle.hepburn
        style.syllables["し"] = nil
        style.syllables["しゃ"] = nil
        let issues = RubyTransliterationValidator.validate(style)
        #expect(issues.contains { $0.input == "し" && $0.problem == "し left as kana" })
        #expect(issues.contains { $0.input == "しゃ" })
    }

    /// Words where the styles differ, in Hepburn, Kunrei-shiki,
    /// Nihon-shiki, passport style, wāpuro, Turkish, Polivanov and Hangul.
    @Test(arguments: [
        ("とうきょう", "とーきょー", ["tōkyō", "tôkyô", "tôkyô", "tokyo", "toukyou", "tôkyô", "токё", "도쿄"]),
        ("まっちゃ", nil, ["matcha", "mattya", "mattya", "matcha", "maccha", "matça", "маття", "맛차"]),
        ("しんぶん", nil, ["shinbun", "sinbun", "sinbun", "shimbun", "shinbun", "şinbun", "симбун", "신분"]),
        ("げんいん", nil, ["gen'in", "gen'in", "gen'in", "genin", "gennin", "gen'in", "гэнъин", "겐인"]),
        ("こんにちは", "こんにちわ", ["konnichiwa", "konnitiwa", "konnitiwa", "konnichiwa", "konnichiha", "konniçiwa", "коннитива", "곤니치와"]),
        ("せんせい", "せんせー", ["sensei", "sensei", "sensei", "sensei", "sensei", "sensei", "сэнсэй", "센세이"]),
        ("コーヒー", nil, ["kōhī", "kôhî", "kôhî", "kohi", "ko-hi-", "kôhî", "кохи", "고히"]),
        ("さむらい", nil, ["samurai", "samurai", "samurai", "samurai", "samurai", "samurai", "самурай", "사무라이"]),
        ("はなぢ", nil, ["hanaji", "hanazi", "hanadi", "hanaji", "hanadi", "hanaci", "ханадзи", "하나지"]),
        ("ヴァイオリン", nil, ["vaiorin", "vaiorin", "vaiorin", "baiorin", "vaiorin", "vaiorin", "вайорин", "바이오린"]),
    ] as [(String, String?, [String])])
    func styles(_ kana: String, _ pronunciation: String?, _ expected: [String]) {
        let written = RubyRomanization.allCases.map { $0.transliterate(kana, pronunciation: pronunciation) }
        #expect(written == expected)
    }

    @Test func namesAreCapitalized() {
        let tokyo = RubyPhrase([.init("東京", reading: "とうきょう", pronunciation: "とーきょー", role: .properNoun)])
        let ibaraki = RubyPhrase([.init("茨城", reading: "いばらき", role: .properNoun)])
        #expect(RubyRomanization.hepburn.transliterate(tokyo) == "Tōkyō")
        #expect(RubyRomanization.polivanov.transliterate(tokyo) == "Токё")
        #expect(RubyRomanization.hangul.transliterate(tokyo) == "도쿄")
        // Turkish capitalizes i as İ; typed romaji stay lowercase.
        #expect(RubyRomanization.turkish.transliterate(ibaraki) == "İbaraki")
        #expect(RubyRomanization.wapuro.transliterate(ibaraki) == "ibaraki")
    }

    @Test func wordsCanBeWrittenTheirOwnWay() {
        var style = RubyTableStyle.hepburn
        style.words["東京"] = "Tokyo"
        let phrase = RubyPhrase([.init("東京", reading: "とうきょう", pronunciation: "とーきょー", role: .properNoun), .init("都", reading: "と")])
        #expect(RubyRomanization(style).transliterate(phrase) == "Tokyoto")
    }

    @Test func stylesAreValues() {
        var style = RubyTableStyle.hepburn
        #expect(RubyRomanization(style) == .hepburn)
        style.syllables["し"] = "si"
        #expect(RubyRomanization(style) != .hepburn)
        #expect(RubyRomanization(style).transliterate("すし") == "susi")
        #expect(RubyRomanization.polivanov.description == "polivanov")
        #expect(Set(RubyRomanization.allCases).count == RubyRomanization.allCases.count)
    }

    @Test func protocolTakesOtherStyles() {
        /// Writes each mora's kind, to show what styles receive.
        struct Kinds: RubyTransliterationStyle {
            func transliterate(_ phrase: RubyPhrase) -> String {
                phrase.morae.map { mora in
                    switch mora.kind {
                    case .syllable: mora.spoken
                    case .geminate: "Q"
                    case .nasal: "N"
                    case .long: "R"
                    case .space: "_"
                    case .other: mora.text
                    }
                }.joined(separator: ".")
            }
        }
        let romanization = RubyRomanization(Kinds())
        #expect(romanization.transliterate("きょうはまっちゃ", pronunciation: "きょーわまっちゃ") == "きょ.R.わ.ま.Q.ちゃ")
        #expect(romanization.transliterate("しんぶん。") == "し.N.ぶ.N.。")
        #expect(romanization.description == "Kinds")
    }

    @Test func moraeResolveWhatKanaLeaveOpen() {
        let morae = RubyPhrase(kana: "ねぇ、ふぁいる").morae
        #expect(morae.map(\.kind) == [.syllable, .long, .other, .syllable, .syllable, .syllable])
        #expect(morae[1].vowel == "e")
        #expect(morae[3].text == "ふぁ" && morae[3].consonant == "f" && morae[3].vowel == "a")
        // A particle は is spoken わ, with or without a pronunciation.
        let particle = RubyPhrase([.init("は", role: .particle)]).morae[0]
        #expect(particle.text == "は" && particle.spoken == "わ" && particle.consonant == "w")
        // A final っ knows what follows the phrase.
        let itta = RubyPhrase([.init("行っ", reading: "いっ")], following: "た")
        #expect(itta.following?.consonant == "t")
        #expect(RubyRomanization.hepburn.transliterate(itta) == "it")
    }

    @Test func hangulAspiratesInsideWords() {
        // こ starts the word unaspirated and is aspirated after it.
        #expect(RubyRomanization.hangul.transliterate("こうこう", pronunciation: "こーこー") == "고코")
        #expect(RubyRomanization.hangul.transliterate("ちゃ ちゃ") == "자 자")
        #expect(RubyRomanization.hangul.transliterate("おちゃ") == "오차")
    }
}
