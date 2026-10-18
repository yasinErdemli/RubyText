import Foundation
import RubyTransliteration
import Synchronization

/// A kana of the text, or a kana with the small one after it, and its
/// romaji: one beat, for romaji under each kana. Or a reading over kanji
/// or digits and its romaji, since the reading is kana too: oo under 大.
package struct RubyKanaRomaji: Hashable, Sendable {
    /// UTF-16 offsets of the kana in the text, or of the kanji or digits
    /// under a reading.
    package let range: Range<Int>
    /// The kana as written: か, カ, きゃ, っ, ー. Under a reading, the
    /// reading as written: おお over 大.
    package let kana: String
    /// The beats of `kana`, each as written: か alone, or お and お for 大's
    /// reading, so it's known once each of them is.
    package let beats: [String]
    /// The beat in romaji: ka, kya, the t of っ before て, n. Under a
    /// reading, the whole reading, as romaji write a word: oo, daigaku.
    package let text: String
    /// Your identifier for the word it's in, from its segments.
    package let wordID: String?
    /// Whether it's the romaji of a reading over kanji or digits, which
    /// show only while the reading does.
    package let isReading: Bool

    init(range: Range<Int>, kana: String, beats: [String]? = nil, text: String, wordID: String?, isReading: Bool = false) {
        self.range = range
        self.kana = kana
        self.beats = beats ?? [kana]
        self.text = text
        self.wordID = wordID
        self.isReading = isReading
    }
}

extension RubyContent {
    /// Each kana of the text with its romaji in `system`, a beat at a time:
    /// わたしは is wa, ta, shi, wa. A kana with the small one after it is
    /// one beat (きゃ is kya), and so are っ, ん and ー on their own.
    ///
    /// Kana are read with what's known of their word: the particle は is
    /// wa, a reading over kana is how they're read, and っ at the end of a
    /// segment doubles what the next one starts with. Kana outside words,
    /// as in text with no analyzer, are read as written. Rewritten text
    /// has none, since its kana aren't the text as written.
    ///
    /// A reading over kanji or digits is kana too, so it has its romaji
    /// under the kanji, the whole reading as one: 大きい is oo, ki, i, and
    /// 大学 is daigaku.
    package func kanaRomaji(in system: RubyRomanization) -> [RubyKanaRomaji] {
        if let cached = kanaRomajiBySystem.withLock({ $0[system] }) { return cached }
        let beats = original == nil ? RubyKanaBeats(content: self, system: system).all : []
        kanaRomajiBySystem.withLock { $0[system] = beats }
        return beats
    }
}

/// Finds the beats of a content's kana, word by word.
private struct RubyKanaBeats {
    let content: RubyContent
    let system: RubyRomanization

    var all: [RubyKanaRomaji] {
        var beats: [RubyKanaRomaji] = []
        var offset = 0
        for word in content.words {
            if offset < word.range.lowerBound {
                beats += plain(text(offset..<word.range.lowerBound), at: offset)
            }
            beats += self.beats(of: word)
            offset = max(offset, word.range.upperBound)
        }
        let end = content.string.utf16.count
        if offset < end {
            beats += plain(text(offset..<end), at: offset)
        }
        return beats
    }

    private func text(_ range: Range<Int>) -> String {
        RubyReadingUnits.substring(of: content.string, utf16Range: range)
    }

    /// The beats of `word`, from the pieces romaji are made of where they
    /// spell it, so each is read with its own reading and grammar.
    private func beats(of word: RubyWord) -> [RubyKanaRomaji] {
        let base = text(word.range)
        let sources = word.romajiSources
        guard !sources.isEmpty, sources.map(\.word.surface).joined() == base else {
            return plain(base, at: word.range.lowerBound, following: sources.last?.next, furigana: word.furigana, wordID: word.wordID)
        }
        var beats: [RubyKanaRomaji] = []
        var offset = word.range.lowerBound
        for source in sources {
            let surface = source.word.surface
            if let phrase = Self.phrase(reading: surface, as: source.word, following: source.next) {
                beats += self.beats(of: phrase, over: surface, at: offset, wordID: word.wordID)
            } else {
                beats += plain(surface, at: offset, following: source.next, furigana: word.furigana, wordID: word.wordID, source: source.word)
            }
            offset += surface.utf16.count
        }
        return beats
    }

    /// `surface`, all kana, read as `word` reads it, if its reading is
    /// kana for kana: as written, or as a reading given over it ({は|わ}).
    private static func phrase(reading surface: String, as word: RubyPhrase.Word, following: String?) -> RubyPhrase? {
        guard !surface.isEmpty, surface.allSatisfy(\.isKana) else { return nil }
        let written = RubyKana.hiragana(surface)
        let reading = RubyKana.hiragana(word.reading)
        if reading == written {
            let read = RubyPhrase.Word(surface, reading: reading, pronunciation: word.pronunciation, role: word.role)
            return RubyPhrase([read], following: following)
        }
        guard reading.count == written.count, reading.allSatisfy(\.isKana) else { return nil }
        return RubyPhrase([RubyPhrase.Word(surface, reading: written, pronunciation: reading, role: word.role)], following: following)
    }

    /// The beats of the kana in `text`, a run at a time, read as written,
    /// and of the readings over its kanji or digits, a reading at a time.
    ///
    /// - Parameters:
    ///   - following: The reading after the text, for a final っ.
    ///   - furigana: Readings over the text's kanji, for a っ before one,
    ///     and for their own romaji.
    ///   - source: The word the text is, if it's one, so a reading over all
    ///     of it is said as the word is.
    private func plain(
        _ text: String,
        at offset: Int,
        following: String? = nil,
        furigana: [RubyReading] = [],
        wordID: String? = nil,
        source: RubyPhrase.Word? = nil
    ) -> [RubyKanaRomaji] {
        let end = offset + text.utf16.count
        // What's read after `position`, for a final っ: a reading over
        // what comes next, or its kana, or what follows the text.
        func next(after position: Int) -> String? {
            guard position < end else { return following }
            if let reading = furigana.first(where: { $0.range.lowerBound == position }) { return reading.text }
            return self.text(position..<end)
        }
        var beats: [RubyKanaRomaji] = []
        var run = ""
        var runStart = offset
        var position = offset
        var readingEnd = offset
        func endRun() {
            guard !run.isEmpty else { return }
            let next = position == end ? following : furigana.first { $0.range.lowerBound == position }?.text
            beats += self.beats(of: RubyPhrase([RubyPhrase.Word(run)], following: next), over: run, at: runStart, wordID: wordID)
            run = ""
        }
        for character in text {
            defer { position += character.utf16.count }
            guard position >= readingEnd else { continue }
            if let reading = furigana.first(where: { $0.range.lowerBound == position && $0.range.upperBound <= end }),
               case let base = self.text(reading.range), !base.allSatisfy(\.isKana),
               let beat = self.beat(of: reading, over: base, following: next(after: reading.range.upperBound), wordID: wordID, word: reading.range == offset..<end ? source : nil) {
                endRun()
                beats.append(beat)
                readingEnd = reading.range.upperBound
            } else if character.isKana {
                if run.isEmpty { runStart = position }
                run.append(character)
            } else {
                endRun()
            }
        }
        endRun()
        return beats
    }

    /// The romaji of `reading`, over `base`, its kanji or digits: the
    /// whole reading written as a word, as `word` says it if it's the
    /// whole word, with each of the reading's beats as written.
    private func beat(of reading: RubyReading, over base: String, following: String?, wordID: String?, word: RubyPhrase.Word?) -> RubyKanaRomaji? {
        let kana = RubyKana.hiragana(reading.text)
        guard !kana.isEmpty, kana.allSatisfy({ $0.isKana || $0 == "ー" }) else { return nil }
        let read = word.map { RubyPhrase.Word(base, reading: $0.reading, pronunciation: $0.pronunciation, role: $0.role, breaks: $0.breaks) }
            ?? RubyPhrase.Word(base, reading: kana)
        let phrase = RubyPhrase([read], following: following)
        let romaji = system.transliterate(phrase)
        guard !romaji.isEmpty else { return nil }
        return RubyKanaRomaji(
            range: reading.range,
            kana: reading.text,
            beats: Self.beats(of: reading.text),
            text: romaji,
            wordID: wordID,
            isReading: true
        )
    }

    /// `kana`'s beats, each as written: a kana, or a kana with the small
    /// one after it (きょ).
    private static func beats(of kana: String) -> [String] {
        let characters = Array(kana)
        let morae = RubyPhrase(kana: RubyKana.hiragana(kana)).morae.filter { $0.kind != .space }
        guard morae.reduce(0, { $0 + $1.text.count }) == characters.count else { return characters.map(String.init) }
        var beats: [String] = []
        var index = 0
        for mora in morae {
            beats.append(String(characters[index..<(index + mora.text.count)]))
            index += mora.text.count
        }
        return beats
    }

    /// `phrase`'s beats, over `surface`, the kana it reads, from `offset`.
    private func beats(of phrase: RubyPhrase, over surface: String, at offset: Int, wordID: String?) -> [RubyKanaRomaji] {
        let kana = Array(surface)
        let morae = phrase.morae.filter { $0.kind != .space }
        // Each mora is one kana, or two joined, so they cover the kana one
        // to one unless converting them changed their count.
        guard morae.reduce(0, { $0 + $1.text.count }) == kana.count else { return [] }
        var beats: [RubyKanaRomaji] = []
        var index = 0
        var position = offset
        for (mora, romaji) in zip(phrase.morae, system.transliterateMorae(phrase)) where mora.kind != .space {
            let written = String(kana[index..<(index + mora.text.count)])
            let length = written.utf16.count
            if !romaji.isEmpty, mora.kind != .other {
                beats.append(RubyKanaRomaji(range: position..<(position + length), kana: written, text: romaji, wordID: wordID))
            }
            index += mora.text.count
            position += length
        }
        return beats
    }
}
