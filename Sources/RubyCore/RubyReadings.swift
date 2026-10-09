import Foundation
import RubyTransliteration

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
    /// Hepburn romaji for the whole word, if it's Japanese.
    package let romaji: String?
    /// What the romaji are made from, to write them in other systems.
    package var romajiSources: [RubyRomajiSource] = []
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

extension RubyWord {
    /// The word's romaji in `system`.
    package func romaji(in system: RubyRomanization) -> String? {
        guard system != .hepburn, romaji != nil, !romajiSources.isEmpty else { return romaji }
        return romajiSources.map { $0.romaji(in: system) }.joined()
    }
}

/// A reading and what romaji need to know about it, so they can be
/// written in any system.
package struct RubyRomajiSource: Hashable, Sendable {
    let reading: String
    let pronunciation: String?
    /// The next word's reading, for a final っ.
    let next: String?
    let breaks: [Int]

    package init(reading: String, pronunciation: String? = nil, next: String? = nil, breaks: [Int] = []) {
        self.reading = reading
        self.pronunciation = pronunciation
        self.next = next
        self.breaks = breaks
    }

    func romaji(in system: RubyRomanization) -> String {
        RubyRomaji.romanize(reading, system: system, pronunciation: pronunciation, next: next, breaks: breaks)
    }
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
        let source = RubyRomajiSource(reading: reading)
        return RubyWord(
            range: offset..<(offset + base.utf16.count),
            furigana: furigana(base: base, reading: reading, offset: offset, force: true),
            romaji: source.romaji(in: .hepburn),
            romajiSources: [source],
            source: .manual
        )
    }

    /// Splits a word's reading over its kanji, leaving kana that the reading
    /// repeats (okurigana) unannotated: 食べ物 + たべもの → 食:た, 物:もの.
    ///
    /// Readings show as written, so katakana stays katakana ({本気|マジ}).
    /// They're matched against the base in hiragana.
    ///
    /// - Parameter force: Annotate the whole base even if it has no kanji,
    ///   for readings the author supplied explicitly.
    package static func furigana(base: String, reading written: String, offset: Int, force: Bool) -> [RubyReading] {
        let reading = RubyKana.hiragana(written)
        guard !reading.isEmpty else { return [] }
        // Converting to hiragana keeps each character in place unless the
        // reading has half-width kana, which it combines (ｶﾞ → が); then
        // show the converted reading.
        let shown = written.utf16.count == reading.utf16.count ? written : reading
        let whole = [RubyReading(range: offset..<(offset + base.utf16.count), text: shown)]

        guard base.contains(where: RubyKana.isKanji) else { return force ? whole : [] }

        // Group the base into alternating runs of kanji and other characters.
        var runs: [(isKanji: Bool, text: String)] = []
        for character in base {
            let kanji = RubyKana.isKanji(character)
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
            $0.isKanji ? "(.+?)" : NSRegularExpression.escapedPattern(for: RubyKana.hiragana($0.text))
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
                if let range = Range(match.range(at: group), in: shown) {
                    readings.append(RubyReading(range: position..<(position + length), text: String(shown[range])))
                }
                group += 1
            }
            position += length
        }
        return readings
    }
}
