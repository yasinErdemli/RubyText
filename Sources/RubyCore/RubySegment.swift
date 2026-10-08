import Foundation

/// Where a segment's reading came from, in priority order: a manual
/// override, a rule, Foundation Models as a tie-breaker, or the dictionary.
public enum ReadingSource: String, Hashable, Sendable, CaseIterable {
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
    public var reading: String?
    public var word: Word?
    public var source: ReadingSource

    /// What's known about a segment's grammar.
    public struct Word: Hashable, Sendable {
        public var partOfSpeech: RubyPartOfSpeech?
        /// The uninflected form, such as 生まれる for 生まれ.
        public var dictionaryForm: String?
        /// Whether this segment grammatically attaches to the one before
        /// it, like a particle or verb ending.
        public var attachesToPrevious: Bool?

        public init(partOfSpeech: RubyPartOfSpeech? = nil, dictionaryForm: String? = nil, attachesToPrevious: Bool? = nil) {
            self.partOfSpeech = partOfSpeech
            self.dictionaryForm = dictionaryForm
            self.attachesToPrevious = attachesToPrevious
        }
    }

    public init(_ base: String, reading: String? = nil, word: Word? = nil, source: ReadingSource = .manual) {
        self.base = base
        self.reading = reading
        self.word = word
        self.source = source
    }
}
