/// One beat of spoken Japanese, as a transliteration style receives it:
/// a syllable such as き or きゃ, っ, ん, a long vowel, or anything that
/// isn't kana.
///
/// The library resolves what kana alone leave open, so styles don't have
/// to: which small kana join the kana before them (きゃ, ふぁ, てぃ),
/// which vowels are long (とうきょう, spoken とーきょー), and which は and
/// へ are particles, spoken わ and え.
public struct RubyMora: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A kana, or a kana with the small one after it: か, きゃ, ふぁ.
        case syllable
        /// っ, doubling the consonant after it.
        case geminate
        /// ん.
        case nasal
        /// A vowel held for another beat: ー, or a kana the pronunciation
        /// lengthens, such as the う of とう.
        case long
        /// A space between parts of a word, such as the pieces of a long
        /// number: nisen nijūroku.
        case space
        /// Anything that isn't kana: punctuation, Latin letters, digits,
        /// and kanji without a reading.
        case other
    }

    public let kind: Kind
    /// The mora as written, in hiragana for kana: きゃ, っ, ん, the う of
    /// とう, ー. Anything else as it is.
    public let text: String
    /// The mora as spoken, where that differs from how it's written: わ
    /// for the particle は, え for the particle へ. Otherwise `text`.
    public let spoken: String
    /// For syllables, the consonant as spoken, written as Hepburn writes
    /// it: k for か, sh for し, ky for きゃ, f for ふぁ, and empty for a
    /// vowel. Styles use it to tell what follows ん or っ.
    public let consonant: String?
    /// For syllables, the vowel as spoken: a, i, u, e, or o. For long
    /// vowels, the vowel held.
    public let vowel: Character?
    /// The index of the word in the phrase this mora belongs to.
    public let word: Int

    /// Every syllable the library recognizes, in hiragana: each kana, and
    /// each kana with a small one it joins (きゃ, ふぁ, てぃ). Small kana
    /// that join nothing are syllables of their own.
    public static let syllables: [String] = hepburn.keys.sorted()

    /// Whether `consonant` is palatalized: followed by a y sound, as in
    /// きゃ, しゃ and や. Cyrillic writes the vowel after it as я, ю, or ё.
    public static func isPalatalized(_ consonant: String) -> Bool {
        consonant.hasSuffix("y") || ["sh", "ch", "j"].contains(consonant)
    }

    init(kind: Kind, text: String, spoken: String? = nil, word: Int) {
        self.kind = kind
        self.text = text
        self.spoken = spoken ?? text
        self.word = word
        if kind == .syllable, let spelling = Self.hepburn[self.spoken], let vowel = spelling.last {
            consonant = String(spelling.dropLast())
            self.vowel = vowel
        } else {
            consonant = nil
            vowel = nil
        }
    }

    init(long text: String, vowel: Character?, word: Int) {
        kind = .long
        self.text = text
        spoken = "ー"
        consonant = nil
        self.vowel = vowel
        self.word = word
    }

    // MARK: Reading kana into morae

    /// The morae of one word: its reading, with long vowels and particles
    /// taken from its pronunciation where it has one.
    static func morae(of word: RubyPhrase.Word, index: Int) -> [RubyMora] {
        let kana = spellingOutRepeatMarks(Array(RubyKana.hiragana(word.reading)))
        let spoken = spokenKana(for: kana, word: word)
        let breaks = Set(word.breaks.filter { $0 > 0 })
        var result: [RubyMora] = []
        var lastVowel: Character?
        var position = 0
        while position < kana.count {
            if breaks.contains(position) {
                result.append(RubyMora(kind: .space, text: " ", word: index))
                lastVowel = nil
            }
            let character = kana[position]
            let next = position + 1 < kana.count ? kana[position + 1] : nil
            defer { position += 1 }
            switch character {
            case "っ":
                result.append(RubyMora(kind: .geminate, text: "っ", word: index))
                continue
            case "ん":
                result.append(RubyMora(kind: .nasal, text: "ん", word: index))
                lastVowel = nil
                continue
            case "ー":
                result.append(RubyMora(long: "ー", vowel: lastVowel, word: index))
                continue
            default:
                break
            }
            if spoken[position] == "ー" {
                result.append(RubyMora(long: String(character), vowel: lastVowel, word: index))
                continue
            }
            let sound = String(spoken[position])
            guard hepburn[sound] != nil else {
                result.append(RubyMora(kind: .other, text: String(character), word: index))
                lastVowel = nil
                continue
            }
            // A small kana joins the kana before it, or stretches its
            // vowel when it repeats it: ねぇ is nē.
            if let next, smallKana.contains(next), sound == String(character) {
                let joined = sound + String(next)
                if hepburn[joined] != nil {
                    let mora = RubyMora(kind: .syllable, text: joined, word: index)
                    result.append(mora)
                    lastVowel = mora.vowel
                    position += 1
                    continue
                }
                let mora = RubyMora(kind: .syllable, text: sound, word: index)
                if hepburn[String(next)]?.last == mora.vowel, mora.vowel != nil, !"ゃゅょゎ".contains(next) {
                    result.append(mora)
                    result.append(RubyMora(long: String(next), vowel: mora.vowel, word: index))
                    lastVowel = mora.vowel
                    position += 1
                    continue
                }
            }
            let mora = RubyMora(kind: .syllable, text: String(character), spoken: sound, word: index)
            result.append(mora)
            lastVowel = mora.vowel
        }
        return result
    }

    /// How each kana of a word is spoken: ー for a long vowel, わ and え
    /// for the particles は and へ, and otherwise as written.
    ///
    /// Without a pronunciation, the second vowel of おう, おお and うう is
    /// read as long, and a particle は or へ as spoken.
    private static func spokenKana(for kana: [Character], word: RubyPhrase.Word) -> [Character] {
        if let pronunciation = word.pronunciation {
            let spoken = spellingOutRepeatMarks(Array(RubyKana.hiragana(pronunciation)))
            if spoken.count == kana.count {
                return zip(kana, spoken).map { written, said in
                    switch (written, said) {
                    case (_, "ー") where written != "ー": "ー"
                    case ("は", "わ"), ("へ", "え"): said
                    default: written
                    }
                }
            }
        }
        if word.role == .particle, kana.count == 1, let particle = particles[kana[0]] {
            return [particle]
        }
        return markingLongVowels(kana)
    }

    /// `kana` with ー for the second vowel of おう, おお and うう, for
    /// readings without a pronunciation, such as numbers read by rule.
    private static func markingLongVowels(_ kana: [Character]) -> [Character] {
        var result = kana
        var lastVowel: Character?
        for (index, character) in kana.enumerated() {
            let isJoined = index + 1 < kana.count && smallKana.contains(kana[index + 1])
            if !isJoined, let lastVowel,
               character == "う" && (lastVowel == "o" || lastVowel == "u") || character == "お" && lastVowel == "o" {
                result[index] = "ー"
                continue
            }
            if let vowel = hepburn[String(character)]?.last {
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

    private static let particles: [Character: Character] = ["は": "わ", "へ": "え"]

    /// The kana of each vowel, to write a long vowel on its own as the
    /// vowel it holds.
    static let vowelKana: [Character: String] = ["a": "あ", "i": "い", "u": "う", "e": "え", "o": "お"]

    /// Small kana, which join the kana before them.
    private static let smallKana: Set<Character> = ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゃ", "ゅ", "ょ", "ゎ"]

    /// Hiragana and the voiced kana ゞ repeats them as.
    private static let voiced = RubyKana.pairs("かがきぎくぐけげこごさざしじすずせぜそぞただちぢつづてでとどはばひびふぶへべほぼうゔ")
    private static let unvoiced = Dictionary(uniqueKeysWithValues: voiced.map { ($0.value, $0.key) })

    /// Each syllable as Hepburn writes it, which gives its consonant and
    /// vowel.
    static let hepburn: [String: String] = [
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
        // Small kana on their own.
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa",
        // Kana with small や, ゆ and よ.
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        // Sounds from other languages.
        "いぇ": "ye", "うぃ": "wi", "うぇ": "we", "うぉ": "wo",
        "きぇ": "kye", "ぎぇ": "gye", "しぇ": "she", "じぇ": "je", "ちぇ": "che", "ぢぇ": "je",
        "にぇ": "nye", "ひぇ": "hye", "びぇ": "bye", "ぴぇ": "pye", "みぇ": "mye", "りぇ": "rye",
        "くぁ": "kwa", "くぃ": "kwi", "くぇ": "kwe", "くぉ": "kwo", "くゎ": "kwa",
        "ぐぁ": "gwa", "ぐぃ": "gwi", "ぐぇ": "gwe", "ぐぉ": "gwo", "ぐゎ": "gwa",
        "すぃ": "si", "ずぃ": "zi",
        "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso",
        "てぃ": "ti", "でぃ": "di", "とぅ": "tu", "どぅ": "du", "てゅ": "tyu", "でゅ": "dyu",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
        "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo", "ゔゅ": "vyu",
    ]
}
