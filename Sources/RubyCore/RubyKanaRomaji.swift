import Foundation
import RubyTransliteration
import Synchronization

/// A kana of the text, or a kana with the small one after it, and its
/// romaji: one beat, for romaji under each kana.
package struct RubyKanaRomaji: Hashable, Sendable {
    /// UTF-16 offsets of the kana in the text.
    package let range: Range<Int>
    /// The kana as written: か, カ, きゃ, っ, ー.
    package let kana: String
    /// The beat in romaji: ka, kya, the t of っ before て, n.
    package let text: String
    /// Your identifier for the word it's in, from its segments.
    package let wordID: String?
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
                beats += plain(surface, at: offset, following: source.next, furigana: word.furigana, wordID: word.wordID)
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

    /// The beats of the kana in `text`, a run at a time, read as written.
    ///
    /// - Parameters:
    ///   - following: The reading after the text, for a final っ.
    ///   - furigana: Readings over the text's kanji, for a っ before one.
    private func plain(
        _ text: String,
        at offset: Int,
        following: String? = nil,
        furigana: [RubyReading] = [],
        wordID: String? = nil
    ) -> [RubyKanaRomaji] {
        var beats: [RubyKanaRomaji] = []
        var run = ""
        var runStart = offset
        var position = offset
        func endRun() {
            guard !run.isEmpty else { return }
            let next = position == offset + text.utf16.count
                ? following
                : furigana.first { $0.range.lowerBound == position }?.text
            beats += self.beats(of: RubyPhrase([RubyPhrase.Word(run)], following: next), over: run, at: runStart, wordID: wordID)
            run = ""
        }
        for character in text {
            if character.isKana {
                if run.isEmpty { runStart = position }
                run.append(character)
            } else {
                endRun()
            }
            position += character.utf16.count
        }
        endRun()
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
