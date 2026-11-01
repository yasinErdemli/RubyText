extension RubyKana {
    /// `text` with its romaji turned into kana, as a Japanese input method
    /// turns it while it's typed: gakusei is がくせい, kitte is きって,
    /// konnichiha is こんにちは.
    ///
    /// It follows the rules people type romaji by, which Foundation's
    /// `latinToHiragana` transform doesn't:
    /// - ん is n before a consonant or at the end, n' or nn: shinbun and
    ///   shinnbun are both しんぶん. nn before a vowel or y is ん and the
    ///   next kana's n, so konnichiha is こんにちは and kinnyuu きんにゅう.
    /// - A doubled consonant is っ: kitte, zasshi, and tch, as in matcha.
    /// - Hepburn and Nihon-shiki spellings both work: shi and si, chi and
    ///   ti, tsu and tu, fu and hu, ja and zya. di and du are ぢ and づ;
    ///   dhi and thi are でぃ and てぃ.
    /// - x or l before a kana makes it small: xa is ぁ, ltsu is っ, xya ゃ.
    /// - - is the long-vowel mark ー, and . , ? ! [ ] are 。、？！「」.
    ///
    /// Romaji typed in capitals becomes katakana (SAMU is サム, raMEN is
    /// らメン), and so does all of it when `asKatakana` is true. Kana,
    /// kanji and anything else in `text` are unchanged, so the result of
    /// one call can be given back with more romaji after it.
    ///
    /// While typing goes on (`isFinished` false), romaji that could still
    /// become something else stays as it is: a lone consonant, as in
    /// がくs, and n or nn at the end, which a vowel could turn into な or
    /// んな. Once typing's finished, a trailing n or nn is ん.
    public static func fromRomaji(_ text: String, isFinished: Bool = true, asKatakana: Bool = false) -> String {
        let characters = Array(text)
        var result = ""
        var index = 0

        /// The character at `offset` from the current one, lowercased, if
        /// it's ASCII.
        func letter(_ offset: Int) -> Character? {
            let place = index + offset
            guard characters.indices.contains(place), characters[place].isASCII else { return nil }
            return Character(characters[place].lowercased())
        }

        /// Appends `kana`, in katakana where the romaji it came from began
        /// with a capital or katakana's asked for.
        func append(_ kana: String) {
            let isCapital = characters[index].isUppercase
            result += asKatakana || isCapital ? katakana(kana) : kana
        }

        /// The longest syllable the romaji from here spells, and how many
        /// characters it takes.
        func longestSyllable() -> (String, Int)? {
            for length in stride(from: 4, through: 1, by: -1) {
                let end = index + length
                guard end <= characters.count else { continue }
                let piece = characters[index..<end]
                guard piece.allSatisfy(\.isASCII) else { continue }
                if let kana = Self.syllables[String(piece).lowercased()] {
                    return (kana, length)
                }
            }
            return nil
        }

        while index < characters.count {
            guard let current = letter(0) else {
                result.append(characters[index])
                index += 1
                continue
            }
            if let mark = Self.marks[current] {
                result += mark
                index += 1
                continue
            }
            if current == "n" {
                let next = letter(1)
                if index + 1 == characters.count {
                    if isFinished { append("ん") } else { result.append(characters[index]) }
                    index += 1
                    continue
                }
                if next == nil {
                    // Kana or anything else after it.
                    append("ん")
                    index += 1
                    continue
                }
                if next == "'" {
                    append("ん")
                    index += 2
                    continue
                }
                if next == "n" {
                    let after = letter(2)
                    if let after, Self.startsSyllable(after) {
                        // konnichiha: ん, then に.
                        append("ん")
                        index += 1
                    } else if index + 2 == characters.count, !isFinished {
                        // A vowel could still follow, as in konni.
                        result.append(contentsOf: characters[index...index + 1])
                        index += 2
                    } else {
                        append("ん")
                        index += 2
                    }
                    continue
                }
                if let next, !Self.startsSyllable(next) {
                    append("ん")
                    index += 1
                    continue
                }
            }
            if Self.consonants.contains(current), current != "n", let next = letter(1),
               next == current || (current == "t" && next == "c" && letter(2) == "h") {
                append("っ")
                index += 1
                continue
            }
            if let (kana, length) = longestSyllable() {
                append(kana)
                index += length
                continue
            }
            // Romaji that isn't a kana yet, or never will be.
            result.append(characters[index])
            index += 1
        }
        return result
    }

    /// Whether `letter`, after an n, makes it part of the next kana:
    /// a vowel, as in na, or y, as in nya.
    private static func startsSyllable(_ letter: Character) -> Bool {
        "aiueoy".contains(letter)
    }

    /// The letters that double into っ.
    private static let consonants = Set("bcdfghjkmnpqrstvwxyz")

    /// What punctuation typed with romaji becomes.
    private static let marks: [Character: String] = [
        "-": "ー", ".": "。", ",": "、", "?": "？", "!": "！", "[": "「", "]": "」",
    ]

    /// Each syllable's romaji, Hepburn and Nihon-shiki, and its hiragana.
    private static let syllables: [String: String] = {
        var table: [String: String] = [
            "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
            "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
            "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
            "sa": "さ", "si": "し", "shi": "し", "su": "す", "se": "せ", "so": "そ",
            "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
            "ta": "た", "ti": "ち", "chi": "ち", "tu": "つ", "tsu": "つ", "te": "て", "to": "と",
            "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
            "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
            "ha": "は", "hi": "ひ", "hu": "ふ", "fu": "ふ", "he": "へ", "ho": "ほ",
            "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
            "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
            "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
            "ya": "や", "yu": "ゆ", "yo": "よ", "ye": "いぇ",
            "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
            "wa": "わ", "wi": "うぃ", "we": "うぇ", "wo": "を",
            "vu": "ゔ", "va": "ゔぁ", "vi": "ゔぃ", "ve": "ゔぇ", "vo": "ゔぉ",
            "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ", "fyu": "ふゅ",
            "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
            "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
            "ja": "じゃ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
            "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",
            "thi": "てぃ", "thu": "てゅ", "dhi": "でぃ", "dhu": "でゅ",
            "twu": "とぅ", "dwu": "どぅ",
            "xtu": "っ", "ltu": "っ", "xtsu": "っ", "ltsu": "っ",
            "xwa": "ゎ", "lwa": "ゎ", "xka": "ゕ", "lka": "ゕ", "xke": "ゖ", "lke": "ゖ",
        ]
        // The small vowels and small y-kana, after x or l.
        for (vowel, small) in ["a": "ぁ", "i": "ぃ", "u": "ぅ", "e": "ぇ", "o": "ぉ"] {
            table["x" + vowel] = small
            table["l" + vowel] = small
        }
        for (sound, small) in ["ya": "ゃ", "yu": "ゅ", "yo": "ょ"] {
            table["x" + sound] = small
            table["l" + sound] = small
        }
        // The y-kana: kya きゃ, and the Nihon-shiki sya, zya, tya, cya and
        // jya beside Hepburn's sha, ja and cha.
        let yBases = [
            "k": "き", "g": "ぎ", "s": "し", "z": "じ", "j": "じ", "t": "ち", "c": "ち", "d": "ぢ",
            "n": "に", "h": "ひ", "b": "び", "p": "ぴ", "m": "み", "r": "り",
        ]
        for (consonant, base) in yBases {
            for (vowel, small) in ["a": "ゃ", "u": "ゅ", "o": "ょ"] {
                table[consonant + "y" + vowel] = base + small
            }
        }
        return table
    }()
}
