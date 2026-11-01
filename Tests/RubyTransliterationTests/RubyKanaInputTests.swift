import RubyTransliteration
import Testing

@Suite struct RubyKanaInputTests {
    @Test("Finished romaji becomes the kana an input method types", arguments: [
        ("gakusei", "がくせい"), ("sensei", "せんせい"), ("watashi", "わたし"),
        ("kitte", "きって"), ("zasshi", "ざっし"), ("matcha", "まっちゃ"), ("chotto", "ちょっと"),
        ("konnichiha", "こんにちは"), ("konnnichiha", "こんにちは"), ("kinnyuu", "きんにゅう"),
        ("shinbun", "しんぶん"), ("shinnbun", "しんぶん"), ("kin'en", "きんえん"), ("kinen", "きねん"),
        ("hon", "ほん"), ("honn", "ほん"), ("sennsei", "せんせい"), ("nn", "ん"),
        ("si", "し"), ("ti", "ち"), ("tu", "つ"), ("hu", "ふ"), ("zya", "じゃ"), ("tya", "ちゃ"),
        ("jaa", "じゃあ"), ("kyou", "きょう"), ("ryokou", "りょこう"), ("nyuu", "にゅう"),
        ("di", "ぢ"), ("du", "づ"), ("dhi", "でぃ"), ("thi", "てぃ"), ("fa", "ふぁ"), ("vu", "ゔ"),
        ("wo", "を"), ("xa", "ぁ"), ("ltsu", "っ"), ("xya", "ゃ"),
        ("ra-men", "らーめん"), ("hai,", "はい、"), ("desu.", "です。"), ("desuka?", "ですか？"),
    ])
    func finished(_ romaji: String, _ kana: String) {
        #expect(RubyKana.fromRomaji(romaji) == kana)
    }

    @Test("Romaji still being typed waits for what comes next", arguments: [
        ("gakus", "がくs"), ("k", "k"), ("ky", "ky"), ("kon", "こn"), ("konn", "こnn"),
        ("konni", "こんに"), ("sennse", "せんせ"), ("kit", "きt"), ("kitt", "きっt"),
    ])
    func unfinished(_ romaji: String, _ kana: String) {
        #expect(RubyKana.fromRomaji(romaji, isFinished: false) == kana)
    }

    @Test("Kana already there stays, so typing can go on after it")
    func kanaStays() {
        #expect(RubyKana.fromRomaji("がくse", isFinished: false) == "がくせ")
        #expect(RubyKana.fromRomaji("こnni", isFinished: false) == "こんに")
        #expect(RubyKana.fromRomaji("学生desu") == "学生です")
        #expect(RubyKana.fromRomaji("nか") == "んか")
    }

    @Test("Capitals, or asking for it, give katakana")
    func katakana() {
        #expect(RubyKana.fromRomaji("SAMU") == "サム")
        #expect(RubyKana.fromRomaji("KO-HI-") == "コーヒー")
        #expect(RubyKana.fromRomaji("raMEN") == "らメン")
        #expect(RubyKana.fromRomaji("kanada", asKatakana: true) == "カナダ")
        #expect(RubyKana.fromRomaji("gakkou", asKatakana: true) == "ガッコウ")
        #expect(RubyKana.fromRomaji("vu", asKatakana: true) == "ヴ")
    }

    @Test("What isn't romaji is left alone")
    func otherText() {
        #expect(RubyKana.fromRomaji("3 hon") == "3 ほん")
        #expect(RubyKana.fromRomaji("") == "")
        #expect(RubyKana.fromRomaji("q") == "q")
    }
}
