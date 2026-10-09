import Foundation

/// Which readings VoiceOver and Read Aloud say in place of the text as
/// written, by where the readings came from.
///
/// Voices read kanji with readings of their own, which mostly agree with
/// the dictionary's. They can't know a reading you supply, such as
/// {宇宙|そら}, and often miss ones that depend on context, such as 3日 as
/// みっか or 辛い as つらい. By default those are spoken as furigana show
/// them, and the voice reads everything else itself, with the more natural
/// pitch it gives words it knows.
///
///     RubyText("{宇宙|そら}を見上げた")
///         .rubySpokenReadings(.all)
///
/// What VoiceOver shows on a braille display stays the text as written.
public struct RubySpokenReadings: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Readings you supply with `{base|reading}` markup or as segments.
    public static let manual = Self(rawValue: 1 << 0)
    /// Readings rules choose, for numbers with counters such as 3日 and
    /// for set phrases.
    public static let rule = Self(rawValue: 1 << 1)
    /// Readings Apple's on-device model chooses with `rubyModelReadings()`.
    public static let model = Self(rawValue: 1 << 2)
    /// Readings from the analyzer's dictionary.
    public static let dictionary = Self(rawValue: 1 << 3)

    /// Every reading except the dictionary's: the ones a voice is most
    /// likely to get wrong. The default.
    public static let corrections: Self = [.manual, .rule, .model]
    /// Every reading, so voices say exactly what furigana show.
    public static let all: Self = [.corrections, .dictionary]

    /// Whether readings from `source` are spoken.
    package func contains(_ source: RubyReadingSource) -> Bool {
        switch source {
        case .manual: contains(Self.manual)
        case .rule: contains(Self.rule)
        case .model: contains(Self.model)
        case .dictionary: contains(Self.dictionary)
        }
    }
}

/// A stretch of text and what a voice should say for it.
package struct RubySpokenText: Hashable, Sendable {
    /// UTF-16 range in the text.
    package let range: Range<Int>
    package let text: String

    package init(range: Range<Int>, text: String) {
        self.range = range
        self.text = text
    }

    /// `text` as an SSML fragment: the words to say, with XML's special
    /// characters escaped.
    package var ssml: String {
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}

/// Text as a voice should read it, and where each part came from.
package struct RubySpokenString: Sendable {
    package let string: String
    /// Where each spoken stretch is in `string`, and in the text it was
    /// spoken from, in order.
    private let replacements: [(spoken: Range<Int>, source: Range<Int>)]

    /// The UTF-16 offset in the text that `offset` in `string` was spoken
    /// from: the start of what replaced it, if anything did.
    package func sourceOffset(_ offset: Int) -> Int {
        var shift = 0
        for replacement in replacements {
            if offset < replacement.spoken.lowerBound { break }
            if offset < replacement.spoken.upperBound { return replacement.source.lowerBound }
            shift = replacement.spoken.upperBound - replacement.source.upperBound
        }
        return offset - shift
    }

    fileprivate init(text: String, speech: [RubySpokenText]) {
        var string = ""
        var replacements: [(spoken: Range<Int>, source: Range<Int>)] = []
        var offset = 0
        for item in speech {
            string += RubyReadingUnits.substring(of: text, utf16Range: offset..<item.range.lowerBound)
            let start = string.utf16.count
            string += item.text
            replacements.append((start..<string.utf16.count, item.range))
            offset = item.range.upperBound
        }
        string += RubyReadingUnits.substring(of: text, utf16Range: offset..<text.utf16.count)
        self.string = string
        self.replacements = replacements
    }
}

extension RubyContent {
    /// Where a voice reading this text as it's shown should say something
    /// else, in order:
    ///
    /// - Text as written says the readings `readings` includes.
    /// - Kana text says nothing else: it's written in its readings.
    /// - Romaji text says each word in kana, as it's read in kana text.
    /// - Text with readings in parentheses says each word once: as written,
    ///   or in its reading if `readings` includes it.
    package func speech(_ readings: RubySpokenReadings) -> [RubySpokenText] {
        guard let original, let rewriteForm else {
            return words.compactMap { word in
                guard readings.contains(word.source), !word.furigana.isEmpty else { return nil }
                let spoken = spelling(of: word)
                return spoken == text(of: word) ? nil : RubySpokenText(range: word.range, text: spoken)
            }
        }
        if rewriteForm == .kana { return [] }
        // Words correspond one to one with the original's.
        return zip(words, original.words).compactMap { word, source in
            let spoken = rewriteForm == .romaji || readings.contains(source.source)
                ? original.spelling(of: source)
                : original.text(of: source)
            guard !word.range.isEmpty, spoken != text(of: word) else { return nil }
            return RubySpokenText(range: word.range, text: spoken)
        }
    }

    /// This text as a voice should read it aloud: with the readings
    /// `readings` includes in place of their words.
    package func spokenString(_ readings: RubySpokenReadings) -> RubySpokenString {
        RubySpokenString(text: string, speech: speech(readings))
    }

    /// `word` as written.
    package func text(of word: RubyWord) -> String {
        RubyReadingUnits.substring(of: string, utf16Range: word.range)
    }

    /// `word` in kana: its readings in place of the kanji they cover, and
    /// its kana as written.
    package func spelling(of word: RubyWord) -> String {
        var spelling = ""
        var position = word.range.lowerBound
        for furigana in word.furigana.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            spelling += RubyReadingUnits.substring(of: string, utf16Range: position..<furigana.range.lowerBound)
            spelling += furigana.text
            position = furigana.range.upperBound
        }
        spelling += RubyReadingUnits.substring(of: string, utf16Range: position..<word.range.upperBound)
        return spelling
    }
}
