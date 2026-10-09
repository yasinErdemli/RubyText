@testable import RubyUI
import Testing

/// Where romaji over a word that wraps may be split between lines.
@Suite struct RubyRomajiBreakTests {
    /// `romaji` split at each place a break is allowed.
    private func breaks(_ romaji: String) -> String {
        let text = Array(romaji)
        var result = ""
        for (index, character) in text.enumerated() {
            if index > 0, RubyRenderer.isRomajiBreak(in: text, at: index) { result += "|" }
            result.append(character)
        }
        return result
    }

    @Test func syllabicNStaysWithItsSyllable() {
        #expect(breaks("benkyō") == "ben|kyō")
        #expect(breaks("san") == "san")
        #expect(breaks("onna") == "on|na")
        #expect(breaks("kin'en") == "kin'|en")
    }

    @Test func nStartingASyllable() {
        #expect(breaks("nani") == "na|ni")
        #expect(breaks("konnyaku") == "kon|nya|ku")
    }

    @Test func passportM() {
        #expect(breaks("shimbun") == "shim|bun")
        #expect(breaks("samma") == "sam|ma")
        #expect(breaks("mame") == "ma|me")
    }

    @Test func doubledConsonantsAndVowels() {
        #expect(breaks("chotto") == "chot|to")
        #expect(breaks("matcha") == "mat|cha")
        #expect(breaks("kitte") == "kit|te")
        #expect(breaks("tōkyō") == "tō|kyō")
        #expect(breaks("nai") == "na|i")
    }
}
