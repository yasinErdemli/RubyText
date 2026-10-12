import Foundation
import RubyTransliteration

/// A stretch of text emphasized as one unit while reading aloud: a word plus
/// the particles and endings attached to it, a reading phrase (文節) such as
/// 吾輩は, 猫で, or 生まれた. Voices pronounce these together, so emphasizing
/// the particle on its own would only flash it briefly.
package nonisolated struct RubyReadingUnit: Sendable {
    /// UTF-16 range in the text.
    package let range: Range<Int>
    package let romaji: String
    /// Approximate length in moras, used to divide a phrase's time.
    package let weight: Double
}

/// When reading starts for a run of units: either a phrase measured by the
/// voice (several units sharing one start) or a single aligned unit.
package nonisolated struct RubyTimelineAnchor: Sendable {
    /// Index of the first unit this anchor covers.
    package let unit: Int
    /// Seconds from the start of the audio.
    package let start: Double
    /// When speech for the anchor's units ends, if known exactly.
    package let end: Double?

    package init(unit: Int, start: Double, end: Double?) {
        self.unit = unit
        self.start = start
        self.end = end
    }
}

package nonisolated enum RubyReadingUnits {
    /// Particles, auxiliaries, and endings that attach to the preceding word.
    private static let attachingWords: Set<String> = [
        // Particles.
        "は", "が", "を", "に", "へ", "で", "と", "や", "の", "も", "か", "ね", "よ", "な", "わ", "ぞ", "さ",
        "から", "まで", "より", "ので", "のに", "けど", "けれど", "けれども", "だけ", "しか", "ほど",
        "など", "って", "ば", "ながら", "たり", "だり",
        // Auxiliaries and verb endings.
        "です", "でした", "でしょう", "ます", "ました", "ません", "ませ", "た", "だ", "だっ", "て",
        "ない", "なかっ", "ぬ", "ず", "う", "よう", "たい", "れる", "られる", "せる", "させる",
        "い", "いる", "いた", "おり",
    ]

    /// Groups words into reading units, attaching particles and endings to
    /// the word directly before them. Uses the tokenizer's grammar when it
    /// provides it, and a list of common particles and endings otherwise.
    ///
    /// - Parameter phrasesAreGiven: Whether a word that doesn't attach to
    ///   the one before it always starts a unit, as in segments an app
    ///   gives, rather than continuing a compound an analyzer split.
    package static func units(in text: String, words: [RubyWord], phrasesAreGiven: Bool = false) -> [RubyReadingUnit] {
        var groups: [(range: Range<Int>, romaji: String, weight: Double)] = []
        for word in words {
            let token = substring(of: text, utf16Range: word.range)
            let previous = groups.last.map { substring(of: text, utf16Range: $0.range) } ?? ""
            let attaches = word.attachesToPrevious ?? attachingWords.contains(token)
            // Kanji right after an all-kanji unit continues a compound noun
            // the tokenizer split, like 日本|語.
            // Likewise for letters and digits split apart, like iPhone|15.
            // A phrase the app starts (今日|何を) is one, though.
            let continuesCompound = !previous.isEmpty
                && !(phrasesAreGiven && word.attachesToPrevious == false)
                && (previous.allSatisfy(\.isKanji) && token.first.map(\.isKanji) == true
                    || previous.allSatisfy(isAlphanumeric) && token.first.map(isAlphanumeric) == true)
            let weight = spokenWeight(of: token, romaji: word.romaji)
            if let last = groups.indices.last,
               groups[last].range.upperBound == word.range.lowerBound,
               attaches || continuesCompound {
                groups[last].range = groups[last].range.lowerBound..<word.range.upperBound
                groups[last].romaji += word.romaji ?? ""
                groups[last].weight += weight
            } else {
                groups.append((word.range, word.romaji ?? "", weight))
            }
        }
        return groups.map { RubyReadingUnit(range: $0.range, romaji: $0.romaji, weight: $0.weight) }
    }

    /// Approximate time a word takes to say, in moras. Numbers and Latin
    /// words have no romaji, but voices still read them out: 2026 is
    /// にせんにじゅうろく and iPhone is アイフォーン, so estimate from their
    /// characters rather than letting them flash by.
    private static func spokenWeight(of token: String, romaji: String?) -> Double {
        if let romaji, !romaji.isEmpty { return moraCount(of: romaji, fallback: 1) }
        let weight = token.reduce(0.0) { total, character in
            if character.isNumber { total + 2 } else if character.isLetter { total + 0.8 } else { total }
        }
        return max(weight, 1)
    }

    /// ASCII or full-width letters and digits, which have no readings.
    private static func isAlphanumeric(_ character: Character) -> Bool {
        (character.isLetter || character.isNumber) && !character.isJapanese
    }

    /// Anchors for units whose starts are given, one for each unit in
    /// order, with when the last ends, if known. Units past the last start
    /// share its anchor.
    package static func anchors(phraseStarts: [Double], end: Double?, units: [RubyReadingUnit]) -> [RubyTimelineAnchor] {
        var anchors = zip(units.indices, phraseStarts).map { RubyTimelineAnchor(unit: $0, start: $1, end: nil) }
        if let end, let last = anchors.popLast() {
            anchors.append(RubyTimelineAnchor(unit: last.unit, start: last.start, end: end))
        }
        return anchors
    }

    /// The unit being spoken at `time`, how far through it is, and how long
    /// ago it started. A run of units sharing one anchor divides the time
    /// until the next anchor by mora count.
    package static func spokenUnit(
        at time: Double,
        anchors: [RubyTimelineAnchor],
        units: [RubyReadingUnit],
        text: String,
        duration totalDuration: Double
    ) -> (unit: Int, progress: Double, elapsed: Double)? {
        guard !units.isEmpty, let index = anchors.lastIndex(where: { $0.start <= time }) else { return nil }
        let anchor = anchors[index]
        let nextUnit = index + 1 < anchors.count ? anchors[index + 1].unit : units.count
        guard anchor.unit < min(nextUnit, units.count) else { return nil }
        let members = anchor.unit..<min(nextUnit, units.count)

        let nextStart = index + 1 < anchors.count ? anchors[index + 1].start : totalDuration
        let end = min(anchor.end ?? nextStart, nextStart)
        // Without an exact end, leave room for the pause punctuation adds.
        var pause = 0.0
        if anchor.end == nil {
            let textEnd = nextUnit < units.count ? units[nextUnit].range.lowerBound : text.utf16.count
            pause = pauseWeight(in: text, utf16Range: units[anchor.unit].range.lowerBound..<textEnd)
        }

        let span = max(end - anchor.start, 0.001)
        let total = members.reduce(0) { $0 + units[$1].weight } + pause
        var position = (time - anchor.start) / span * total
        var consumed = 0.0
        for member in members {
            let weight = units[member].weight
            // During a trailing pause, keep the last unit emphasized.
            if position < weight || member == members.upperBound - 1 {
                let unitStart = anchor.start + consumed / total * span
                return (member, min(max(position / weight, 0), 1), max(0, time - unitStart))
            }
            position -= weight
            consumed += weight
        }
        return nil
    }

    /// Index of the unit containing a UTF-16 offset (binary search).
    package static func unit(containing offset: Int, in units: [RubyReadingUnit]) -> Int? {
        var low = 0
        var high = units.count
        while low < high {
            let mid = (low + high) / 2
            if offset < units[mid].range.lowerBound {
                high = mid
            } else if offset >= units[mid].range.upperBound {
                low = mid + 1
            } else {
                return mid
            }
        }
        return nil
    }

    /// Approximate length of romaji in moras.
    package static func moraCount(of romaji: String, fallback: Int) -> Double {
        let characters = Array(romaji.lowercased())
        guard !characters.isEmpty else { return Double(max(fallback, 1)) }
        var count = 0.0
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if "aeiou".contains(character) {
                count += 1
            } else if "āīūēōâîûêô".contains(character) {
                count += 2 // Long vowel.
            } else if character == "n", next.map({ !"aeiouy".contains($0) }) ?? true {
                count += 1 // Syllabic ん.
            } else if let next, next == character, !"aeioun".contains(character) {
                count += 1 // Doubled consonant (っ).
            }
        }
        return max(count, 1)
    }

    /// Extra weight for the pause punctuation adds within a phrase.
    private static func pauseWeight(in text: String, utf16Range range: Range<Int>) -> Double {
        let pauses = substring(of: text, utf16Range: range).filter { "。、．，！？!?,.".contains($0) }.count
        return Double(pauses) * 1.5
    }

    package static func substring(of text: String, utf16Range range: Range<Int>) -> String {
        let utf16 = text.utf16
        guard let lower = utf16.index(utf16.startIndex, offsetBy: range.lowerBound, limitedBy: utf16.endIndex),
              let upper = utf16.index(lower, offsetBy: range.count, limitedBy: utf16.endIndex)
        else { return "" }
        return String(text[lower..<upper])
    }
}
