import Foundation

/// Where a segment's reading came from, in priority order: a manual
/// override, a rule, Foundation Models as a tie-breaker, or the dictionary.
public enum RubyReadingSource: String, Hashable, Sendable, CaseIterable {
    case manual, rule, model, dictionary
}

/// A piece of text with its reading and grammar, as plain data independent
/// of any other segment's position.
///
/// An array of segments covers a whole text: joining every `base` returns
/// the original string. Segments with nothing to say about their text, such
/// as punctuation, have `reading` and `word` both `nil`.
public struct RubySegment: Hashable, Sendable {
    public var base: String
    /// Hiragana reading of the whole segment, covering any kanji and
    /// okurigana together. `nil` for kana, punctuation, and numbers.
    /// Analyzers may give it in katakana; RubyText reads either.
    public var reading: String?
    /// How the reading is spoken, if the analyzer knows: とーきょー for
    /// とうきょう, わ for the particle は, おう for 追う. Romaji use it for
    /// long vowels; without it, they follow spelling rules.
    public var pronunciation: String?
    public var word: Word?
    public var source: RubyReadingSource
    /// Your identifier for the word the segment is part of, such as an ID
    /// in your own data. Consecutive segments with the same ID are one
    /// word, so a word given in pieces, each with its own reading, is
    /// tapped, read by VoiceOver, colored and spaced as one:
    ///
    ///     RubySegment("食", reading: "た", wordID: "food"),
    ///     RubySegment("べ", wordID: "food"),
    ///     RubySegment("物", reading: "もの", wordID: "food"),
    ///
    /// The word takes its grammar, `word`, from its first segment. Its ID
    /// comes back in `RubyWordInfo`, and `RubyWordColors.wordIDs(_:)` and
    /// `RubyFuriganaFilter.showing(wordIDs:)` choose words by it. Words
    /// apart from each other can share an ID, but words next to each other
    /// need different ones.
    public var wordID: String?
    /// Offsets in `reading` where romaji put a space, so long numbers read
    /// in parts: nisen nijūroku.
    package var romajiBreaks: [Int] = []

    /// What's known about a segment's grammar. An analyzer that knows
    /// nothing about it can leave `word` `nil`: segments with a reading or
    /// any letters or digits are still words.
    public struct Word: Hashable, Sendable {
        public var partOfSpeech: RubyPartOfSpeech?
        /// The uninflected form, such as 生まれる for 生まれ.
        public var dictionaryForm: String?
        /// Whether this segment grammatically attaches to the one before
        /// it, like a particle or verb ending, in the same reading phrase
        /// (文節). `nil` lets RubyText decide from a list of common
        /// particles and endings.
        ///
        /// In segments you give `RubyText(segments:)`, `false` always
        /// starts a new phrase. Analyzers often split compound words
        /// (経済|政策), so in their segments a kanji word after an all-kanji
        /// phrase continues it.
        public var attachesToPrevious: Bool?
        /// Whether this is the name of a person or place, which romaji
        /// capitalize: Tōkyō, Tanaka.
        public var isProperNoun: Bool

        public init(
            partOfSpeech: RubyPartOfSpeech? = nil,
            dictionaryForm: String? = nil,
            attachesToPrevious: Bool? = nil,
            isProperNoun: Bool = false
        ) {
            self.partOfSpeech = partOfSpeech
            self.dictionaryForm = dictionaryForm
            self.attachesToPrevious = attachesToPrevious
            self.isProperNoun = isProperNoun
        }
    }

    public init(
        _ base: String,
        reading: String? = nil,
        pronunciation: String? = nil,
        word: Word? = nil,
        source: RubyReadingSource = .manual,
        wordID: String? = nil
    ) {
        self.base = base
        self.reading = reading
        self.pronunciation = pronunciation
        self.word = word
        self.source = source
        self.wordID = wordID
    }
}
