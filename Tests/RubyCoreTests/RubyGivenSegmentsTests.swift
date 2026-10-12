import RubyCore
import Testing

/// Segments an app gives: words in pieces, joined by their IDs, and
/// phrases where the app starts them.
@Suite struct RubyGivenSegmentsTests {
    /// 日本の食べ物を食べました。, with 食べ物 and 食べました in pieces so
    /// each reading sits over its own kanji, as an app's data has them.
    private static let food = RubyContent.content(for: [
        RubySegment("日本", reading: "にほん", word: .init(attachesToPrevious: false), wordID: "nihon"),
        RubySegment("の", word: .init(attachesToPrevious: true), wordID: "no"),
        RubySegment("食", reading: "た", word: .init(attachesToPrevious: false), wordID: "food"),
        RubySegment("べ", wordID: "food"),
        RubySegment("物", reading: "もの", wordID: "food"),
        RubySegment("を", word: .init(attachesToPrevious: true), wordID: "o"),
        RubySegment("食", reading: "た", word: .init(attachesToPrevious: false), wordID: "eat"),
        RubySegment("べました", wordID: "eat"),
        RubySegment("。", source: .dictionary),
    ])

    @Test func piecesWithOneIDAreOneWord() {
        let words = Self.food.words
        #expect(words.map(\.range) == [0..<2, 2..<3, 3..<6, 6..<7, 7..<12])
        #expect(words.map(\.wordID) == ["nihon", "no", "food", "o", "eat"])
        // Each reading stays over its own kanji.
        #expect(words[2].furigana.map(\.range) == [3..<4, 5..<6])
        #expect(words[2].furigana.map(\.text) == ["た", "もの"])
        // Kana without a reading is read as written.
        #expect(words.map(\.romaji) == ["nihon", "no", "tabemono", "o", "tabemashita"])
        #expect(Self.food.dictionaryWords == words.map(\.range))
    }

    @Test func wordDetailsGiveTheID() {
        let food = RubyWordInfo.info(for: Self.food.dictionaryWords[2], in: Self.food)
        #expect(food.text == "食べ物")
        #expect(food.reading == "たべもの")
        #expect(food.romaji == "tabemono")
        #expect(food.wordID == "food")
    }

    /// Pieces are written as one word in every system: 禁|煙 is kin'en,
    /// not kinen.
    @Test func piecesAreWrittenAsOneWord() {
        let content = RubyContent.content(for: [
            RubySegment("禁", reading: "きん", wordID: "kinen"),
            RubySegment("煙", reading: "えん", wordID: "kinen"),
        ])
        #expect(content.words.map(\.romaji) == ["kin'en"])
        #expect(content.words.map { $0.romaji(in: .kunrei) } == ["kin'en"])
    }

    /// Words apart can share an ID; only consecutive pieces join.
    @Test func wordsApartStayApart() {
        let content = RubyContent.content(for: [
            RubySegment("猫", reading: "ねこ", wordID: "cat"),
            RubySegment("と", wordID: "to"),
            RubySegment("猫", reading: "ねこ", wordID: "cat"),
        ])
        #expect(content.words.map(\.range) == [0..<1, 1..<2, 2..<3])
    }

    /// A word with an ID of its own is one in word details, though its
    /// grammar would join it to the word before.
    @Test func wordsWithIDsStandAlone() {
        let verb = RubySegment.Word(partOfSpeech: .verb, dictionaryForm: "読む")
        let ending = RubySegment.Word(partOfSpeech: .auxiliary, attachesToPrevious: true)
        let words: [RubySegment] = [RubySegment("読ん", reading: "よん", word: verb), RubySegment("だ", word: ending)]
        #expect(RubyContent.content(for: words).dictionaryWords == [0..<3])
        let withIDs = zip(words, ["read", "past"]).map { segment, id in
            var segment = segment
            segment.wordID = id
            return segment
        }
        #expect(RubyContent.content(for: withIDs).dictionaryWords == [0..<2, 2..<3])
    }

    // MARK: Phrases

    /// 今日｜何を: 何 starts a phrase, as the app says, though a kanji word
    /// after an all-kanji one would otherwise continue it.
    @Test func givenPhraseStartsWin() {
        let content = RubyContent.content(for: [
            RubySegment("今日", reading: "きょう", word: .init(attachesToPrevious: false)),
            RubySegment("何", reading: "なに", word: .init(attachesToPrevious: false)),
            RubySegment("を", word: .init(attachesToPrevious: true)),
            RubySegment("食べる", reading: "たべる", word: .init(attachesToPrevious: false)),
        ])
        #expect(content.readingUnits.map(\.range) == [0..<2, 2..<4, 4..<7])
    }

    /// Left to RubyText, a kanji word after an all-kanji one continues it.
    @Test func undecidedKanjiContinueACompound() {
        let content = RubyContent.content(for: [
            RubySegment("日本", reading: "にほん"),
            RubySegment("語", reading: "ご"),
            RubySegment("を", word: .init(attachesToPrevious: true)),
        ])
        #expect(content.readingUnits.map(\.range) == [0..<4])
    }

    @Test func piecesOfAWordAreInOnePhrase() {
        #expect(Self.food.readingUnits.map(\.range) == [0..<3, 3..<7, 7..<12])
    }

    // MARK: Timings

    /// Phrases are emphasized from the starts given for them, the last
    /// until its end.
    @Test func givenStartsTimeTheirPhrases() {
        let units = Self.food.readingUnits
        let anchors = RubyReadingUnits.anchors(phraseStarts: [0, 0.8, 1.5], end: 2.5, units: units)
        func spoken(at time: Double) -> (unit: Int, progress: Double)? {
            RubyReadingUnits.spokenUnit(at: time, anchors: anchors, units: units, text: Self.food.string, duration: 3)
                .map { ($0.unit, $0.progress) }
        }
        #expect(spoken(at: 0.1)?.unit == 0)
        #expect(spoken(at: 0.9)?.unit == 1)
        #expect(spoken(at: 1.6)?.unit == 2)
        // Done by its end, though the recording goes on.
        #expect(spoken(at: 2.6)?.unit == 2)
        #expect(spoken(at: 2.6)?.progress == 1)
    }

    /// Phrases past the last start share its time, by their length.
    @Test func phrasesWithoutStartsShareTheLast() {
        let units = Self.food.readingUnits
        let anchors = RubyReadingUnits.anchors(phraseStarts: [0, 1], end: nil, units: units)
        #expect(anchors.map(\.unit) == [0, 1])
        let spoken = RubyReadingUnits.spokenUnit(at: 2.9, anchors: anchors, units: units, text: Self.food.string, duration: 3)
        #expect(spoken?.unit == 2)
    }

    /// Starts past the last phrase are left out.
    @Test func extraStartsAreLeftOut() {
        let units = Self.food.readingUnits
        let anchors = RubyReadingUnits.anchors(phraseStarts: [0, 1, 2, 3], end: 4, units: units)
        #expect(anchors.map(\.unit) == [0, 1, 2])
        #expect(anchors.last?.end == 4)
    }
}

// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
extension RubyGivenSegmentsTests {
    /// An analyzer's segments still join the compounds it splits:
    /// IPAdic reads 自然|言語|処理, each a word of its own.
    @Test func analyzersCompoundsStayOnePhrase() {
        let content = RubyContent.content(for: "自然言語処理を学ぶ")
        #expect(content.words.prefix(3).map(\.attachesToPrevious) == [false, false, false])
        #expect(content.readingUnits.map(\.range) == [0..<7, 7..<9])
    }
}
#endif
