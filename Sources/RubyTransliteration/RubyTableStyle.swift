/// A transliteration style written as data: how each syllable is
/// written, and rules for ん, っ, long vowels, particles, names and
/// punctuation.
///
/// Start from a built-in style and change what differs:
///
///     var style = RubyTableStyle.hepburn
///     style.syllables["し"] = "si"          // a kana written differently
///     style.words["東京"] = "Tokyo"          // a word written its own way
///     style.longVowels = .marked([:])       // long vowels unmarked
///
/// Or build one for another alphabet from its consonants and vowels with
/// `init(name:onsets:vowels:palatalVowels:exceptions:longVowels:)`.
public struct RubyTableStyle: RubyTransliterationStyle, CustomStringConvertible {
    /// How a style writes long vowels.
    public enum LongVowels: Hashable, Sendable {
        /// The vowel before is marked as `marks` writes it: o becomes ō
        /// with `RubyTableStyle.macrons`. Vowels it doesn't list stay as
        /// they are, so `.marked([:])` leaves long vowels unmarked (Tokyo).
        /// Long vowels written with い, as in せんせい, are spelled out:
        /// sensei.
        case marked([String: String])
        /// As the kana spell them, the way Japanese is typed: とう is tou,
        /// ー a hyphen (ko-hi-).
        case spelled
    }

    /// How a style writes the particles は and へ.
    public enum Particles: Hashable, Sendable {
        /// As spoken: wa and e.
        case pronounced
        /// As spelled: ha and he.
        case spelled
    }

    /// A name for the style, such as hepburn.
    public var name: String
    /// How each syllable is written, by its hiragana: "し": "shi",
    /// "きゃ": "kya". `RubyMora.syllables` lists every one the library
    /// recognizes; `RubyTransliterationValidator` finds any missing.
    public var syllables: [String: String]
    /// Syllables written differently after a different vowel, such as い
    /// as й in Cyrillic: самурай.
    public var syllablesAfterVowel: [String: String] = [:]
    /// ん.
    public var nasal = "n"
    /// ん before a vowel or y, which an apostrophe sets apart in Hepburn:
    /// gen'in, kin'yōbi.
    public var nasalBeforeVowel = "n'"
    /// ん before b, m and p, which some styles write as m: shimbun.
    public var nasalBeforeLabial = "n"
    /// What っ is written as before a syllable that starts with each
    /// prefix, such as t before ch in Hepburn: matcha. Before anything
    /// else, it doubles the first letter: kitte.
    public var geminates: [String: String] = [:]
    public var longVowels: LongVowels
    public var particles = Particles.pronounced
    /// Words written their own way, by how they're written in Japanese,
    /// such as "東京": "Tokyo".
    public var words: [String: String] = [:]
    /// Whether names of people and places start with a capital: Tōkyō.
    public var capitalizesProperNouns = true
    /// Capitals for letters whose uppercase depends on the language, such
    /// as İ for i in Turkish.
    public var capitals: [Character: String] = [:]
    /// How Japanese punctuation is written: 、 as a comma, 「」 as “”.
    public var punctuation: [Character: String] = Self.latinPunctuation

    /// A style writing each syllable as `syllables` says, by hiragana.
    public init(name: String, syllables: [String: String], longVowels: LongVowels = .marked(Self.macrons)) {
        self.name = name
        self.syllables = syllables
        self.longVowels = longVowels
    }

    /// A style for an alphabet, writing each syllable as its consonant and
    /// vowel.
    ///
    /// - Parameters:
    ///   - name: The style's name, such as hepburn.
    ///   - onsets: Each consonant as Hepburn writes it (k, sh, ch, ts, f,
    ///     j, and ky, gy for those before a small や, ゆ or よ), and how this
    ///     style writes it. The empty string is a syllable with no
    ///     consonant.
    ///   - vowels: How a, i, u, e and o are written.
    ///   - palatalVowels: How vowels are written after a palatalized
    ///     consonant (`RubyMora.isPalatalized(_:)`), if differently, as
    ///     Cyrillic writes кя and ся.
    ///   - exceptions: Syllables written otherwise, by hiragana.
    ///   - longVowels: How long vowels are written.
    public init(
        name: String,
        onsets: [String: String],
        vowels: [Character: String],
        palatalVowels: [Character: String]? = nil,
        exceptions: [String: String] = [:],
        longVowels: LongVowels = .marked(Self.macrons)
    ) {
        var syllables: [String: String] = [:]
        for kana in RubyMora.syllables {
            guard let hepburn = RubyMora.hepburn[kana], let vowel = hepburn.last else { continue }
            let consonant = String(hepburn.dropLast())
            let vowelTable = RubyMora.isPalatalized(consonant) ? palatalVowels ?? vowels : vowels
            if let onset = onsets[consonant], let written = vowelTable[vowel] {
                syllables[kana] = onset + written
            }
        }
        syllables.merge(exceptions) { $1 }
        self.init(name: name, syllables: syllables, longVowels: longVowels)
    }

    public var description: String { name }

    public func transliterate(_ phrase: RubyPhrase) -> String {
        var writer = RubyTransliterationWriter(punctuation: punctuation)
        // Where each word starts in the text, to capitalize names.
        var starts: [(word: Int, offset: Int)] = []
        var replaced: Int?
        let morae = phrase.morae
        for (index, mora) in morae.enumerated() {
            if index == 0 || morae[index - 1].word != mora.word {
                starts.append((mora.word, writer.text.count))
                replaced = nil
                if let written = words[phrase.words[mora.word].surface] {
                    writer.append(written)
                    replaced = mora.word
                }
            }
            if replaced == mora.word { continue }
            let previous = index > 0 ? morae[index - 1] : nil
            switch mora.kind {
            case .syllable:
                writer.append(spelling(of: mora, after: previous))
            case .geminate:
                let next = index + 1 < morae.count ? morae[index + 1] : phrase.following
                // Silent before a vowel or punctuation, and at the end.
                guard let next, next.kind == .syllable, next.consonant?.isEmpty == false else { continue }
                writer.append(geminate(before: spelling(of: next, after: nil)))
            case .nasal:
                let next = index + 1 < morae.count && morae[index + 1].kind == .syllable ? morae[index + 1] : nil
                if let consonant = next?.consonant, consonant.isEmpty || consonant.hasPrefix("y") {
                    writer.append(nasalBeforeVowel)
                } else if let first = next?.consonant?.first, "bmp".contains(first) {
                    writer.append(nasalBeforeLabial)
                } else {
                    writer.append(nasal)
                }
            case .long:
                writeLong(mora, after: previous, to: &writer)
            case .space:
                writer.space()
            case .other:
                writer.write(other: Character(mora.text))
            }
        }
        guard capitalizesProperNouns else { return writer.text }
        return capitalizing(writer.text, phrase: phrase, starts: starts)
    }

    /// Each mora on its own, as `transliterate(_:)` would write it: a
    /// syllable as the table spells it, っ as the consonant it doubles, ん
    /// as `nasal`, whatever follows. A long vowel is written as the style
    /// spells it, if it does (u, or - for ー), and otherwise as the vowel
    /// it holds, since there's no vowel before it to mark: とう is to, o in
    /// Hepburn and to, u in wāpuro. Words in `words`, and names, are
    /// written beat by beat all the same.
    public func transliterateMorae(_ phrase: RubyPhrase) -> [String] {
        let morae = phrase.morae
        return morae.indices.map { index in
            let mora = morae[index]
            let previous = index > 0 ? morae[index - 1] : nil
            switch mora.kind {
            case .syllable:
                return spelling(of: mora, after: previous)
            case .geminate:
                let next = index + 1 < morae.count ? morae[index + 1] : phrase.following
                guard let next, next.kind == .syllable, next.consonant?.isEmpty == false else { return "" }
                return geminate(before: spelling(of: next, after: nil))
            case .nasal:
                return nasal
            case .long:
                let vowel = RubyMora(kind: .syllable, text: mora.text, word: mora.word)
                switch longVowels {
                case .spelled:
                    return mora.text == "ー" ? "-" : spelling(of: vowel, after: previous)
                case .marked:
                    if mora.text == "い" { return spelling(of: vowel, after: previous) }
                    guard let kana = mora.vowel.flatMap({ RubyMora.vowelKana[$0] }) else { return "" }
                    return spelling(of: RubyMora(kind: .syllable, text: kana, word: mora.word), after: nil)
                }
            case .space, .other:
                return ""
            }
        }
    }

    /// The written form of a syllable, which `previous` comes before.
    private func spelling(of mora: RubyMora, after previous: RubyMora?) -> String {
        let key = particles == .pronounced ? mora.spoken : mora.text
        if let previous, let vowel = previous.vowel, vowel != mora.vowel, let written = syllablesAfterVowel[key] {
            return written
        }
        if let written = syllables[key] { return written }
        // A kana with a small one the table doesn't have: each on its own.
        return key.map { syllables[String($0)] ?? String($0) }.joined()
    }

    /// What っ is written as before `next`, the following syllable as
    /// written.
    private func geminate(before next: String) -> String {
        let prefix = geminates.keys.filter(next.hasPrefix).max { $0.count < $1.count }
        return prefix.flatMap { geminates[$0] } ?? next.first.map(String.init) ?? ""
    }

    private func writeLong(_ mora: RubyMora, after previous: RubyMora?, to writer: inout RubyTransliterationWriter) {
        let vowel = RubyMora(kind: .syllable, text: mora.text, word: mora.word)
        switch longVowels {
        case .spelled:
            writer.append(mora.text == "ー" ? "-" : spelling(of: vowel, after: previous))
        case .marked(let marks):
            if mora.text == "い" {
                writer.append(spelling(of: vowel, after: previous))
            } else if case let text = writer.text, let written = marks.keys.filter(text.hasSuffix).max(by: { $0.count < $1.count }) {
                writer.replaceLast(written.count, with: marks[written] ?? written)
            }
        }
    }

    /// `text` with the first letter of each proper noun capitalized.
    private func capitalizing(_ text: String, phrase: RubyPhrase, starts: [(word: Int, offset: Int)]) -> String {
        var characters = Array(text)
        for (index, start) in starts.enumerated() where phrase.words[start.word].role == .properNoun {
            let end = index + 1 < starts.count ? starts[index + 1].offset : characters.count
            guard let first = characters[start.offset..<end].firstIndex(where: \.isLetter) else { continue }
            let letter = characters[first]
            let capital = capitals[letter] ?? letter.uppercased()
            if capital.count == 1 { characters[first] = Character(capital) }
        }
        return String(characters)
    }

    // MARK: Built-in styles

    /// Macrons for long vowels: ā, ī, ū, ē, ō.
    public static let macrons = ["a": "ā", "i": "ī", "u": "ū", "e": "ē", "o": "ō"]
    /// Circumflexes for long vowels: â, î, û, ê, ô.
    public static let circumflexes = ["a": "â", "i": "î", "u": "û", "e": "ê", "o": "ô"]

    /// Japanese punctuation as Latin punctuation.
    public static let latinPunctuation: [Character: String] = [
        "、": ",", "。": ".", "，": ",", "．": ".", "！": "!", "？": "?",
        "「": "“", "」": "”", "『": "‘", "』": "’",
    ]

    /// Modified Hepburn: shi, chi, tsu, fu, ji, gen'in, matcha, and long
    /// vowels with macrons.
    public static let hepburn: RubyTableStyle = {
        var style = RubyTableStyle(name: "hepburn", syllables: RubyMora.hepburn)
        style.geminates = ["ch": "t"]
        return style
    }()

    /// Kunrei-shiki: si, ti, tu, hu, zi, sya, and long vowels with
    /// circumflexes.
    public static let kunrei: RubyTableStyle = {
        var style = RubyTableStyle(name: "kunrei", syllables: RubyMora.hepburn, longVowels: .marked(circumflexes))
        style.syllables.merge([
            "し": "si", "ち": "ti", "つ": "tu", "ふ": "hu", "じ": "zi", "ぢ": "zi", "づ": "zu",
            "しゃ": "sya", "しゅ": "syu", "しょ": "syo", "しぇ": "sye",
            "ちゃ": "tya", "ちゅ": "tyu", "ちょ": "tyo", "ちぇ": "tye",
            "じゃ": "zya", "じゅ": "zyu", "じょ": "zyo", "じぇ": "zye",
            "ぢゃ": "zya", "ぢゅ": "zyu", "ぢょ": "zyo", "ぢぇ": "zye",
        ]) { $1 }
        return style
    }()

    /// Nihon-shiki: Kunrei-shiki keeping each kana distinct: di, du, wo,
    /// and hwa for ふぁ.
    public static let nippon: RubyTableStyle = {
        var style = kunrei
        style.name = "nippon"
        style.syllables.merge([
            "ぢ": "di", "づ": "du", "ぢゃ": "dya", "ぢゅ": "dyu", "ぢょ": "dyo", "ぢぇ": "dye",
            "を": "wo", "ゐ": "wi", "ゑ": "we",
            "ふぁ": "hwa", "ふぃ": "hwi", "ふぇ": "hwe", "ふぉ": "hwo",
            "つぁ": "twa", "つぃ": "twi", "つぇ": "twe", "つぉ": "two",
        ]) { $1 }
        return style
    }()

    /// Passport Hepburn: no long-vowel marks, m before b, m and p, no
    /// apostrophe, and b for ヴ.
    public static let passport: RubyTableStyle = {
        var style = hepburn
        style.name = "passport"
        style.longVowels = .marked([:])
        style.nasalBeforeVowel = "n"
        style.nasalBeforeLabial = "m"
        style.syllables.merge([
            "ゔ": "bu", "ゔぁ": "ba", "ゔぃ": "bi", "ゔぇ": "be", "ゔぉ": "bo", "ゔゅ": "byu",
        ]) { $1 }
        return style
    }()

    /// Wāpuro: kana as typed, so each kana keeps its own spelling (di,
    /// du, wo, xa for a small ぁ), long vowels and particles are spelled
    /// as written, and ん before a vowel is nn.
    public static let wapuro: RubyTableStyle = {
        var style = hepburn
        style.name = "wapuro"
        style.longVowels = .spelled
        style.particles = .spelled
        style.nasalBeforeVowel = "nn"
        style.geminates = [:]
        style.capitalizesProperNouns = false
        style.syllables.merge([
            "ぢ": "di", "づ": "du", "ぢゃ": "dya", "ぢゅ": "dyu", "ぢょ": "dyo", "ぢぇ": "dye",
            "を": "wo", "ゐ": "wi", "ゑ": "we",
            "ぁ": "xa", "ぃ": "xi", "ぅ": "xu", "ぇ": "xe", "ぉ": "xo",
            "ゃ": "xya", "ゅ": "xyu", "ょ": "xyo", "ゎ": "xwa",
            "てぃ": "thi", "でぃ": "dhi", "とぅ": "twu", "どぅ": "dwu", "てゅ": "thu", "でゅ": "dhu",
        ]) { $1 }
        return style
    }()

    /// Hepburn for Turkish readers: ş, ç and c for sh, ch and j, long
    /// vowels with circumflexes, and İ as the capital of i.
    public static let turkish: RubyTableStyle = {
        var style = hepburn
        style.name = "turkish"
        style.syllables = hepburn.syllables.mapValues { spelling in
            spelling.replacing("sh", with: "ş").replacing("ch", with: "ç").replacing("j", with: "c")
        }
        style.geminates = ["ç": "t"]
        style.longVowels = .marked(circumflexes)
        style.capitals = ["i": "İ"]
        return style
    }()

    /// Polivanov, in Cyrillic: суси, симбун, самурай, with long vowels
    /// unmarked.
    public static let polivanov: RubyTableStyle = {
        var style = RubyTableStyle(
            name: "polivanov",
            onsets: [
                "": "", "k": "к", "s": "с", "sh": "с", "t": "т", "ch": "т", "ts": "ц", "n": "н",
                "h": "х", "f": "ф", "m": "м", "y": "", "r": "р", "w": "в", "g": "г", "z": "дз",
                "j": "дз", "d": "д", "b": "б", "p": "п", "v": "в",
                "ky": "к", "gy": "г", "ny": "н", "hy": "х", "by": "б", "py": "п", "my": "м",
                "ry": "р", "fy": "ф", "ty": "т", "dy": "д", "vy": "в", "kw": "кв", "gw": "гв",
            ],
            vowels: ["a": "а", "i": "и", "u": "у", "e": "э", "o": "о"],
            palatalVowels: ["a": "я", "i": "и", "u": "ю", "e": "е", "o": "ё"],
            longVowels: .marked([:])
        )
        style.syllablesAfterVowel = ["い": "й"]
        style.nasal = "н"
        style.nasalBeforeVowel = "нъ"
        style.nasalBeforeLabial = "м"
        style.punctuation.merge(["「": "«", "」": "»", "『": "„", "』": "“"]) { $1 }
        return style
    }()
}

/// Writes transliterated text, spacing it around punctuation as Latin
/// text does.
struct RubyTransliterationWriter {
    private(set) var text = ""
    let punctuation: [Character: String]
    /// Whether the next word is spaced from what's before it, after a
    /// comma, full stop, or closing quote.
    private var spacesNext = false

    init(punctuation: [Character: String]) {
        self.punctuation = punctuation
    }

    mutating func append(_ string: String) {
        guard let first = string.first else { return }
        if spacesNext, first.isLetter || first.isNumber { text += " " }
        spacesNext = false
        text += string
    }

    /// A space, unless there's one already.
    mutating func space() {
        if let last = text.last, last != " " { text += " " }
        spacesNext = false
    }

    mutating func replaceLast(_ count: Int, with string: String) {
        text.removeLast(min(count, text.count))
        text += string
    }

    /// Punctuation or other text that isn't kana.
    mutating func write(other character: Character) {
        let written = punctuation[character]
        switch character {
        case "、", "。", "，", "．", "！", "？":
            text += written ?? String(character)
            spacesNext = true
        case "「", "『":
            if spacesNext || text.last.map({ $0.isLetter || $0.isNumber }) == true { text += " " }
            spacesNext = false
            text += written ?? String(character)
        case "」", "』":
            text += written ?? String(character)
            spacesNext = true
        case "・", "\u{3000}":
            // The middle dot separates words: ジョン・スミス is jon sumisu.
            space()
        default:
            append(written ?? Self.ascii(character))
        }
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
}
