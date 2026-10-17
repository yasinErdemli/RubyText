import RubyTransliteration
import Testing

/// Romaji a beat at a time, as romaji under each kana write them.
@Suite struct RubyMoraeTests {
    private func morae(
        _ kana: String,
        pronunciation: String? = nil,
        role: RubyPhrase.Word.Role = .other,
        following: String? = nil,
        in system: RubyRomanization = .hepburn
    ) -> [String] {
        system.transliterateMorae(RubyPhrase([.init(kana, pronunciation: pronunciation, role: role)], following: following))
    }

    @Test func eachBeatIsWrittenOnItsOwn() {
        #expect(morae("わたし") == ["wa", "ta", "shi"])
        #expect(morae("きゃく") == ["kya", "ku"])
        // ん is n on its own, with no apostrophe or m.
        #expect(morae("しんぶん") == ["shi", "n", "bu", "n"])
        #expect(morae("げんいん") == ["ge", "n", "i", "n"])
        #expect(morae("しんぶん", in: .passport) == ["shi", "n", "bu", "n"])
        // Names aren't capitalized, a beat being no name.
        #expect(morae("たなか", role: .properNoun) == ["ta", "na", "ka"])
    }

    @Test func particlesAreWrittenAsTheStyleWritesThem() {
        #expect(morae("は", role: .particle) == ["wa"])
        #expect(morae("へ", role: .particle) == ["e"])
        #expect(morae("を", role: .particle) == ["o"])
        #expect(morae("は") == ["ha"])
        #expect(morae("は", role: .particle, in: .wapuro) == ["ha"])
    }

    @Test func smallTsuIsTheConsonantItDoubles() {
        #expect(morae("きって") == ["ki", "t", "te"])
        #expect(morae("まっちゃ") == ["ma", "t", "cha"])
        #expect(morae("まっちゃ", in: .kunrei) == ["ma", "t", "tya"])
        // At the end, it doubles what follows; before nothing, it has
        // nothing to write.
        #expect(morae("いっ", following: "た") == ["i", "t"])
        #expect(morae("あっ") == ["a", ""])
    }

    /// With no vowel before it to mark, a long vowel is the vowel it holds,
    /// unless the style spells long vowels out.
    @Test func longVowelsAreTheVowelHeldOrAsSpelled() {
        #expect(morae("とうきょう", pronunciation: "とーきょー") == ["to", "o", "kyo", "o"])
        #expect(morae("コーヒー") == ["ko", "o", "hi", "i"])
        #expect(morae("とうきょう", pronunciation: "とーきょー", in: .kunrei) == ["to", "o", "kyo", "o"])
        #expect(morae("とうきょう", pronunciation: "とーきょー", in: .wapuro) == ["to", "u", "kyo", "u"])
        #expect(morae("コーヒー", in: .wapuro) == ["ko", "-", "hi", "-"])
        // い after e is spelled out, as in whole words.
        #expect(morae("せんせい", pronunciation: "せんせー") == ["se", "n", "se", "i"])
    }

    @Test func punctuationAndSpacesHaveNothing() {
        #expect(morae("あ、い") == ["a", "", "i"])
        let number = RubyPhrase([.init("2026", reading: "にせんにじゅうろく", breaks: [3])])
        let beats = RubyRomanization.hepburn.transliterateMorae(number)
        #expect(beats.count == number.morae.count)
        #expect(beats.filter(\.isEmpty).count == 1)
    }

    /// Styles that aren't tables write each beat as a phrase of its own:
    /// ん and っ as the final consonant they'd add, and a long vowel,
    /// which Hangul doesn't write, as the vowel held.
    @Test func otherStylesWriteEachBeat() {
        #expect(morae("しんぶん", in: .hangul) == ["시", "ㄴ", "부", "ㄴ"])
        #expect(morae("きって", in: .hangul) == ["기", "ㅅ", "데"])
        #expect(morae("とうきょう", pronunciation: "とーきょー", in: .hangul) == ["도", "오", "교", "오"])
    }
}
