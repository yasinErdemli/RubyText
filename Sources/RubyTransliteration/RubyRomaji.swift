/// Converts kana to Hepburn romaji, with no dictionary and nothing beyond
/// the standard library.
///
/// Long vowels are written with macrons (kyōto, kōhī, jū), except えい and
/// いい, which Hepburn spells out (sensei, ii). Kana alone can't tell
/// whether おう is one long vowel or two (東京 is tōkyō but 思う omou), or
/// whether は is the particle wa: pass a pronunciation where you know it,
/// or use RubyCore, which finds both with its dictionary.
public enum RubyRomaji {
    /// Hepburn romaji for text written in kana: きょうと is kyōto, まっちゃ
    /// matcha, しんぶん shinbun.
    ///
    /// Japanese punctuation becomes Latin punctuation (、 is a comma, 「」
    /// are “”), and full-width letters and digits become ASCII. Kanji stay
    /// as they are, since reading them needs a dictionary.
    ///
    /// - Parameters:
    ///   - kana: Hiragana, katakana, or both.
    ///   - pronunciation: How `kana` is spoken, kana for kana, such as
    ///     とーきょー for とうきょう or わ for the particle は. Without one,
    ///     おう, おお and うう are read as long vowels.
    public static func hepburn(_ kana: String, pronunciation: String? = nil) -> String {
        hepburn(kana, pronunciation: pronunciation, next: nil)
    }

    /// Hepburn romaji for a word's `reading`.
    ///
    /// - Parameters:
    ///   - next: The following word's reading, so a final っ doubles the
    ///     consonant after it: 入っ before た is it, making itta.
    ///   - breaks: Offsets in the reading where romaji put a space.
    package static func hepburn(_ reading: String, pronunciation: String?, next: String?, breaks: [Int] = []) -> String {
        if !breaks.isEmpty {
            let characters = Array(reading)
            let bounds = [0] + breaks.filter { 0 < $0 && $0 < characters.count } + [characters.count]
            let parts = zip(bounds, bounds.dropFirst()).map { String(characters[$0..<$1]) }
            return parts.enumerated().map { index, part in
                hepburn(part, pronunciation: nil, next: index + 1 < parts.count ? parts[index + 1] : next)
            }.joined(separator: " ")
        }
        let kana = spellingOutRepeatMarks(Array(RubyKana.hiragana(reading)))
        let spoken = pronunciation.map { spellingOutRepeatMarks(Array(RubyKana.hiragana($0))) }
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
        let following = next.flatMap { morae(in: Array(RubyKana.hiragana($0))).first }
        var result = ""
        // After a comma or full stop, the next word is spaced from it.
        var spacesNext = false
        func append(_ text: String) {
            if spacesNext, let first = text.first, first.isLetter || first.isNumber || first == "“" || first == "‘" {
                result += " "
            }
            spacesNext = false
            result += text
        }

        for (index, mora) in pieces.enumerated() {
            let after = index + 1 < pieces.count ? pieces[index + 1] : following
            switch mora {
            case .syllable(let romaji):
                append(romaji)
            case .sokuon:
                // Doubles the next consonant, and っち is tch. Before a
                // vowel, punctuation, or at the end, it's silent.
                guard case .syllable(let syllable)? = after, let first = syllable.first, !vowels.contains(first) else { continue }
                append(syllable.hasPrefix("ch") ? "t" : String(first))
            case .n:
                // ん before a vowel or y in the same word takes an
                // apostrophe: gen'in, kin'yōbi, but gohan o.
                append("n")
                if index + 1 < pieces.count, case .syllable(let syllable) = pieces[index + 1],
                   let first = syllable.first, vowels.contains(first) || first == "y" {
                    result += "'"
                }
            case .long:
                lengthenLastVowel(of: &result)
            case .other(let character):
                if let mark = clauseEnds[character] {
                    result += mark
                    spacesNext = true
                } else if let quote = openingQuotes[character] {
                    if result.last.map({ $0.isLetter || $0.isNumber }) == true { result += " " }
                    append(quote)
                } else if let quote = closingQuotes[character] {
                    result += quote
                    spacesNext = true
                } else if character == "・" || character == "\u{3000}" {
                    // The middle dot separates words: ジョン・スミス is jon sumisu.
                    if result.last != " " { result += " " }
                } else {
                    append(ascii(character))
                }
            }
        }
        return result
    }

    /// A romaji syllable or a kana resolved against its neighbors.
    private enum Mora {
        /// A kana, or a kana with a small one after it: kya, fa.
        case syllable(String)
        /// っ, doubling the consonant after it.
        case sokuon
        /// ん.
        case n
        /// ー, lengthening the vowel before it.
        case long
        /// Anything that isn't kana: punctuation, Latin, kanji.
        case other(Character)
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

    /// `kana` with the repeat marks ゝ and ゞ spelled out: いすゞ is いすず,
    /// こゝろ こころ.
    private static func spellingOutRepeatMarks(_ kana: [Character]) -> [Character] {
        var result = kana
        for index in result.indices.dropFirst() {
            let previous = result[index - 1]
            switch result[index] {
            case "ゝ": result[index] = unvoiced[previous] ?? previous
            case "ゞ": result[index] = voiced[previous] ?? previous
            default: break
            }
        }
        return result
    }

    /// Splits kana into morae, combining small kana with the one before
    /// (きゃ is kya, ふぁ fa). っ, ん and ー stay as markers for `hepburn`
    /// to resolve against their neighbors.
    private static func morae(in kana: [Character]) -> [Mora] {
        var result: [Mora] = []
        var index = 0
        while index < kana.count {
            let character = kana[index]
            defer { index += 1 }
            switch character {
            case "っ":
                result.append(.sokuon)
                continue
            case "ー":
                result.append(.long)
                continue
            case "ん":
                result.append(.n)
                continue
            default:
                break
            }
            guard let romaji = single[character] else {
                result.append(.other(character))
                continue
            }
            guard index + 1 < kana.count, let small = smallKana[kana[index + 1]] else {
                result.append(.syllable(romaji))
                continue
            }
            if small.count == 1, romaji.last == small.first {
                // A small kana repeating the vowel stretches it: ねぇ is nē.
                result.append(.syllable(romaji))
                result.append(.long)
                index += 1
            } else if let combined = combine(character, romaji, with: small) {
                result.append(.syllable(combined))
                index += 1
            } else {
                result.append(.syllable(romaji))
            }
        }
        return result
    }

    /// A kana followed by a small one: き + ゃ is kya, し + ゃ sha, て + ぃ
    /// ti, う + ぇ we. `nil` if they don't combine, such as あぉ.
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

    /// ASCII for a full-width letter, digit or symbol (Ａ, ３, ！), or the
    /// character as it is.
    private static func ascii(_ character: Character) -> String {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              (0xFF01...0xFF5E).contains(scalar.value),
              let narrow = Unicode.Scalar(scalar.value - 0xFEE0)
        else { return String(character) }
        return String(narrow)
    }

    /// Punctuation ending a clause or sentence, which the next word is
    /// spaced from.
    private static let clauseEnds: [Character: String] = [
        "、": ",", "。": ".", "，": ",", "．": ".", "！": "!", "？": "?",
    ]
    private static let openingQuotes: [Character: String] = ["「": "“", "『": "‘"]
    private static let closingQuotes: [Character: String] = ["」": "”", "』": "’"]

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]
    private static let macrons: [Character: Character] = ["a": "ā", "i": "ī", "u": "ū", "e": "ē", "o": "ō"]

    /// Hiragana and the voiced kana ゞ repeats them as.
    private static let voiced = RubyKana.pairs("かがきぎくぐけげこごさざしじすずせぜそぞただちぢつづてでとどはばひびふぶへべほぼうゔ")
    private static let unvoiced = Dictionary(uniqueKeysWithValues: voiced.map { ($0.value, $0.key) })

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
