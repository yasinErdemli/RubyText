import Foundation

/// Converts readings to Hepburn romaji, without Foundation's transforms so
/// the core keeps working where they're unavailable.
///
/// Long vowels are written with macrons (Tōkyō, kōhī, jū), except えい and
/// いい, which Hepburn spells out (sensei, ii). Whether おう is long comes
/// from the analyzer's pronunciation when it has one: 東京 is pronounced
/// トーキョー, but 思う stays omou and 湖 mizuumi.
package nonisolated enum RubyRomaji {
    /// Hepburn romaji for a word's hiragana or katakana `reading`.
    ///
    /// - Parameters:
    ///   - pronunciation: How the reading is spoken, from the analyzer, such
    ///     as とーきょー for とうきょう or わ for the particle は. Without
    ///     one, おう, おお and うう are read as long vowels.
    ///   - next: The following word's reading, so a final っ doubles the
    ///     consonant after it: 入っ before た is it, making itta.
    package static func hepburn(_ reading: String, pronunciation: String? = nil, next: String? = nil) -> String {
        let kana = Array(RubyReadings.hiragana(reading))
        let spoken = pronunciation.map { Array(RubyReadings.hiragana($0)) }
        var effective = kana
        if let spoken, spoken.count == kana.count {
            for index in kana.indices {
                switch (kana[index], spoken[index]) {
                // A long vowel, except えい and いい, which keep their い.
                case (let written, "ー") where written != "い": effective[index] = "ー"
                // Particles pronounced differently from their spelling.
                case ("は", "わ"), ("へ", "え"): effective[index] = spoken[index]
                default: break
                }
            }
        } else {
            effective = markingLongVowels(kana)
        }

        let pieces = morae(in: effective)
        let following = next.flatMap { morae(in: Array(RubyReadings.hiragana($0))).first }
        var result = ""
        for (index, mora) in pieces.enumerated() {
            let after = index + 1 < pieces.count ? pieces[index + 1] : following
            switch mora {
            case "っ":
                // Double the next consonant: っち is tch, before a vowel or
                // at the end of the text it's silent.
                guard let after, let first = after.first, !vowels.contains(first) else { continue }
                result += after.hasPrefix("ch") ? "t" : String(first)
            case "n":
                // ん before a vowel or y takes an apostrophe: gen'in, kin'yōbi.
                result += "n"
                if let first = after?.first, vowels.contains(first) || first == "y" { result += "'" }
            case "ー":
                lengthenLastVowel(of: &result)
            default:
                result += mora
            }
        }
        return result
    }

    /// `kana` with ー for the second vowel of おう, おお and うう, for
    /// readings without a pronunciation, such as numbers read by rule.
    private static func markingLongVowels(_ kana: [Character]) -> [Character] {
        var result = kana
        var lastVowel: Character?
        for (index, character) in kana.enumerated() {
            let isSmall = index + 1 < kana.count && smallKana[kana[index + 1]] != nil
            if !isSmall, let lastVowel,
               character == "う" && (lastVowel == "o" || lastVowel == "u") || character == "お" && lastVowel == "o" {
                result[index] = "ー"
                continue
            }
            if let romaji = single[character], let vowel = romaji.last, vowels.contains(vowel) {
                lastVowel = vowel
            } else if character != "ー" {
                lastVowel = nil
            }
        }
        return result
    }

    /// Splits kana into romaji morae, combining small kana with the one
    /// before (きゃ is kya, ふぁ fa). っ, ん and ー stay as markers for
    /// `hepburn` to resolve against their neighbors.
    private static func morae(in kana: [Character]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < kana.count {
            let character = kana[index]
            defer { index += 1 }
            switch character {
            case "っ", "ー":
                result.append(String(character))
                continue
            case "ん":
                result.append("n")
                continue
            default:
                break
            }
            guard let romaji = single[character] else {
                result.append(String(character))
                continue
            }
            if index + 1 < kana.count, let small = smallKana[kana[index + 1]],
               let combined = combine(character, romaji, with: small) {
                result.append(combined)
                index += 1
            } else {
                result.append(romaji)
            }
        }
        return result
    }

    /// A kana followed by a small one: き + ゃ is kya, し + ゃ sha, て + ぃ
    /// ti, う + ぇ we. `nil` if they don't combine, such as あぁ.
    private static func combine(_ kana: Character, _ romaji: String, with small: String) -> String? {
        let consonant = String(romaji.dropLast())
        guard let vowel = romaji.last, vowels.contains(vowel) else { return nil }
        switch kana {
        case "う": return "w" + small.suffix(1)
        case "い": return small == "e" ? "ye" : nil
        case "く", "ぐ": return small.hasPrefix("y") ? consonant + small : consonant + "w" + small.suffix(1)
        default: break
        }
        guard !consonant.isEmpty else { return nil }
        if small.hasPrefix("y") {
            // しゃ, ちゃ and じゃ drop the y: sha, cha, ja.
            if vowel == "i" && ["sh", "ch", "j"].contains(consonant) { return consonant + small.dropFirst() }
            return consonant + small
        }
        return consonant + small
    }

    private static func lengthenLastVowel(of romaji: inout String) {
        guard let index = romaji.lastIndex(where: { vowels.contains($0) }),
              index == romaji.index(before: romaji.endIndex),
              let long = macrons[romaji[index]]
        else { return }
        romaji.replaceSubrange(index...index, with: String(long))
    }

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]
    private static let macrons: [Character: Character] = ["a": "ā", "i": "ī", "u": "ū", "e": "ē", "o": "ō"]

    /// Small kana and the sound they add to the kana before them.
    private static let smallKana: [Character: String] = [
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o", "ゎ": "wa",
    ]

    /// Romaji for each hiragana on its own, including small kana that
    /// don't follow a kana they combine with.
    private static let single: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "o",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ゔ": "vu", "ヵ": "ka", "ヶ": "ke",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa",
    ]
}
