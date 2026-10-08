import Foundation

/// A reading attached to a range of the source text. Offsets are UTF-16.
package struct RubyReading: Hashable, Sendable {
    package let range: Range<Int>
    package let text: String
}

/// A word in the source text with its readings.
package struct RubyWord: Hashable, Sendable {
    /// UTF-16 offsets of the word in the source text.
    package let range: Range<Int>
    /// Hiragana readings for the kanji parts of the word.
    package let furigana: [RubyReading]
    /// Romaji for the whole word, if it's Japanese.
    package let romaji: String?
    /// Whether the word grammatically attaches to the one before it, like a
    /// particle or verb ending. `nil` lets reading phrases fall back to a
    /// list of common particles and endings.
    package var attachesToPrevious: Bool? = nil
    /// The word's grammatical role, if the tokenizer reported one.
    package var partOfSpeech: RubyPartOfSpeech? = nil
    /// The uninflected form, such as 生まれる for 生まれ, used to match
    /// vocabulary in any conjugation.
    package var dictionaryForm: String? = nil
    /// Where the word's reading came from.
    package var source: ReadingSource = .dictionary
}

/// Grammatical roles, in the categories learners are usually taught.
public enum RubyPartOfSpeech: String, CaseIterable, Hashable, Sendable {
    case noun
    case verb
    /// い-adjectives and な-adjectives (静か, 綺麗).
    case adjective
    case adverb
    case particle
    /// Auxiliaries such as です, ます, た, ない.
    case auxiliary
    /// Words that only modify nouns, such as この and 大きな.
    case adnominal
    case conjunction
    case prefix
    case interjection
    /// Symbols and anything unclassified.
    case other
}

/// Reading helpers shared by the tokenizer and manual readings. Pure
/// functions, so not tied to the main actor.
package nonisolated enum RubyReadings {
    /// A word whose reading was supplied with `{base|reading}` markup.
    package static func word(manualBase base: String, reading: String, offset: Int) -> RubyWord {
        RubyWord(
            range: offset..<(offset + base.utf16.count),
            furigana: furigana(base: base, reading: reading, offset: offset, force: true),
            romaji: reading.applyingTransform(.toLatin, reverse: false),
            source: .manual
        )
    }

    /// Splits a word's reading over its kanji, leaving kana that the reading
    /// repeats (okurigana) unannotated: 食べ物 + たべもの → 食:た, 物:もの.
    ///
    /// - Parameter force: Annotate the whole base even if it has no kanji,
    ///   for readings the author supplied explicitly.
    package static func furigana(base: String, reading: String, offset: Int, force: Bool) -> [RubyReading] {
        let reading = hiragana(reading)
        guard !reading.isEmpty else { return [] }
        let whole = [RubyReading(range: offset..<(offset + base.utf16.count), text: reading)]

        guard base.contains(where: isKanji) else { return force ? whole : [] }

        // Group the base into alternating runs of kanji and other characters.
        var runs: [(isKanji: Bool, text: String)] = []
        for character in base {
            let kanji = isKanji(character)
            if let last = runs.indices.last, runs[last].isKanji == kanji {
                runs[last].text.append(character)
            } else {
                runs.append((kanji, String(character)))
            }
        }
        guard runs.count > 1 else { return whole }

        // Kana runs must appear literally in the reading; each kanji run
        // takes whatever lies between them.
        let pattern = "^" + runs.map {
            $0.isKanji ? "(.+?)" : NSRegularExpression.escapedPattern(for: hiragana($0.text))
        }.joined() + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: reading, range: NSRange(reading.startIndex..., in: reading))
        else { return whole }

        var readings: [RubyReading] = []
        var group = 1
        var position = offset
        for run in runs {
            let length = run.text.utf16.count
            if run.isKanji {
                if let range = Range(match.range(at: group), in: reading) {
                    readings.append(RubyReading(range: position..<(position + length), text: String(reading[range])))
                }
                group += 1
            }
            position += length
        }
        return readings
    }

    /// Readings transcribe kana as spelled; particles are pronounced
    /// differently when they stand alone.
    package static func romaji(for token: String, transcription: String) -> String {
        switch token {
        case "は": "wa"
        case "へ": "e"
        case "を": "o"
        default: transcription
        }
    }

    package static func hiragana(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? text
    }

    package static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic || "々〆ヵヶ".unicodeScalars.contains(scalar)
        }
    }

    package static func isJapanese(_ character: Character) -> Bool {
        isKanji(character) || character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, // Hiragana
                 0x30A0...0x30FF, // Katakana
                 0x31F0...0x31FF, // Katakana phonetic extensions
                 0xFF66...0xFF9F: // Half-width katakana
                true
            default:
                false
            }
        }
    }
}
