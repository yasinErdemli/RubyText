import Foundation
import RubyTransliteration

/// What's known about a word in a `RubyText`, passed to word tap handlers.
public struct RubyWordInfo: Identifiable, Hashable, Sendable {
    /// UTF-16 range of the word in the text, with markup removed.
    public let range: Range<Int>
    /// The word as written, with conjugated endings: 生まれた.
    public let text: String
    /// The whole word in kana: うまれた.
    public let reading: String
    public let romaji: String
    /// The uninflected form, if it differs from `text`: 生まれる.
    public let dictionaryForm: String?
    public let partOfSpeech: RubyPartOfSpeech?
    /// The word's JLPT level: its hardest kanji's level.
    public let jlptLevel: RubyJLPTLevel?
    /// Each kanji in the word, with its JLPT level, or `nil` if beyond it.
    public let kanji: [Kanji]
    /// Where the word's reading came from. For a word with readings from
    /// several places, such as a number read by a rule with a counter from
    /// the dictionary, the first of manual, rule, and model.
    public let source: ReadingSource

    public struct Kanji: Hashable, Sendable {
        public let character: Character
        public let level: RubyJLPTLevel?
    }

    public var id: Range<Int> { range }

    /// The details of the dictionary word covering `range` in `content`,
    /// with romaji in `romanization`.
    package static func info(for range: Range<Int>, in content: RubyContent, romanization: RubyRomanization = .hepburn) -> RubyWordInfo {
        let text = RubyReadingUnits.substring(of: content.string, utf16Range: range)
        let tokens = content.words.filter { range.contains($0.range.lowerBound) }

        // Spell the word in kana: readings replace the kanji they cover.
        let reading = tokens.map(content.spelling(of:)).joined()

        let head = tokens.first
        // A noun with する (勉強した) is listed as 勉強する.
        let isSuruVerb = head?.partOfSpeech == .noun && tokens.dropFirst().first?.dictionaryForm == "する"
        let dictionaryForm: String? = if let head, isSuruVerb {
            RubyReadingUnits.substring(of: content.string, utf16Range: head.range) + "する"
        } else if tokens.count > 1 && head?.partOfSpeech == .noun {
            // A noun with suffixes (田中さん) has no other form.
            nil
        } else {
            head?.dictionaryForm
        }
        return RubyWordInfo(
            range: range,
            text: text,
            reading: reading,
            romaji: tokens.compactMap { $0.romaji(in: romanization) }.joined(),
            dictionaryForm: dictionaryForm == text ? nil : dictionaryForm,
            partOfSpeech: isSuruVerb ? .verb : head?.partOfSpeech,
            jlptLevel: RubyJLPTLevel.level(of: text, dictionaryForm: nil, vocabulary: [:]),
            kanji: text.filter(RubyJLPTKanji.isGraded).map { Kanji(character: $0, level: RubyJLPTKanji.level(of: $0)) },
            source: ReadingSource.allCases.first { source in tokens.contains { $0.source == source } } ?? .dictionary
        )
    }
}

extension RubyPartOfSpeech {
    /// A name to show learners.
    public var localizedName: LocalizedStringResource {
        switch self {
        case .noun: "Noun"
        case .verb: "Verb"
        case .adjective: "Adjective"
        case .adverb: "Adverb"
        case .particle: "Particle"
        case .auxiliary: "Auxiliary"
        case .adnominal: "Pre-noun adjectival"
        case .conjunction: "Conjunction"
        case .prefix: "Prefix"
        case .interjection: "Interjection"
        case .other: "Other"
        }
    }
}
