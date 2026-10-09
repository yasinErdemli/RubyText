/// Converts between hiragana and katakana, with no dictionary and nothing
/// beyond the standard library. `Character` tells kanji and kana apart:
/// `isKanji`, `isKana`, `isHiragana`, `isKatakana`, `isJapanese`.
public enum RubyKana {
    /// `text` with its katakana as hiragana: トウキョウ is とうきょう.
    ///
    /// The long-vowel mark stays (コーヒー is こーひー), where Foundation's
    /// transform spells it out (こおひい). Half-width katakana is widened
    /// first (ｶﾞｯｺｳ is がっこう). ヵ and ヶ stay as they are: in 3ヶ月
    /// they're read か and こ, so they act as kanji. Everything else is
    /// unchanged.
    public static func hiragana(_ text: String) -> String {
        shifting(widened(text), by: -0x60) { scalar in
            // ァ through ヴ, and the repeat marks ヽ and ヾ.
            (0x30A1...0x30F4).contains(scalar) || (0x30FD...0x30FE).contains(scalar)
        }
    }

    /// `text` with its hiragana as katakana: とうきょう is トウキョウ.
    /// Half-width katakana is widened; everything else is unchanged.
    public static func katakana(_ text: String) -> String {
        shifting(widened(text), by: 0x60) { scalar in
            // ぁ through ゖ, and the repeat marks ゝ and ゞ.
            (0x3041...0x3096).contains(scalar) || (0x309D...0x309E).contains(scalar)
        }
    }

    /// `text` with each scalar `shifts` accepts moved by `offset`.
    private static func shifting(_ text: String, by offset: Int32, where shifts: (UInt32) -> Bool) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if shifts(scalar.value), let shifted = Unicode.Scalar(UInt32(Int32(scalar.value) + offset)) {
                scalars.append(shifted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // MARK: Half-width katakana

    /// `text` with half-width katakana and punctuation (U+FF61–U+FF9F) at
    /// full width, voicing marks joined to the kana before them (ｶﾞ is
    /// ガ); everything else unchanged.
    ///
    /// Works on scalars: ﾞ and ﾟ extend the character before them, so ｶﾞ
    /// is one `Character`.
    private static func widened(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0xFF61...0xFF9F).contains($0.value) }) else { return text }
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let previous = result.last.map(Character.init)
            switch scalar {
            case "\u{FF9E}":
                if let previous, let voiced = voiced[previous] {
                    result.replaceSubrange(result.index(before: result.endIndex)..., with: voiced.unicodeScalars)
                } else {
                    result.append("\u{309B}") // ゛
                }
            case "\u{FF9F}":
                if let previous, let semivoiced = semivoiced[previous] {
                    result.replaceSubrange(result.index(before: result.endIndex)..., with: semivoiced.unicodeScalars)
                } else {
                    result.append("\u{309C}") // ゜
                }
            default:
                if let wide = fullWidth[Character(scalar)] {
                    result.append(contentsOf: wide.unicodeScalars)
                } else {
                    result.append(scalar)
                }
            }
        }
        return String(result)
    }

    /// Full-width forms of half-width katakana and punctuation.
    private static let fullWidth: [Character: Character] = Dictionary(
        uniqueKeysWithValues: zip(
            "｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ",
            "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン"
        )
    )

    /// Katakana and the voiced kana a ﾞ makes of them.
    private static let voiced = pairs("カガキギクグケゲコゴサザシジスズセゼソゾタダチヂツヅテデトドハバヒビフブヘベホボウヴワヷヲヺ")

    /// Katakana and the kana a ﾟ makes of them.
    private static let semivoiced = pairs("ハパヒピフプヘペホポ")

    /// A dictionary from each even-numbered character of `text` to the one
    /// after it.
    static func pairs(_ text: String) -> [Character: Character] {
        let characters = Array(text)
        return Dictionary(uniqueKeysWithValues: stride(from: 0, to: characters.count - 1, by: 2).map {
            (characters[$0], characters[$0 + 1])
        })
    }
}

extension Character {
    /// Whether this is a kanji, including the repeat mark 々, 〆, and the
    /// small ヵ and ヶ that counters use (3ヶ月).
    public var isKanji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic || "々〆ヵヶ".unicodeScalars.contains(scalar)
        }
    }

    /// Whether this is hiragana, including small kana, the voicing marks,
    /// and the repeat marks ゝ and ゞ.
    public var isHiragana: Bool {
        unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }

    /// Whether this is katakana, full or half width, including the
    /// long-vowel mark ー and the repeat marks ヽ and ヾ, but not the
    /// middle dot ・.
    public var isKatakana: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30A1...0x30FA, 0x30FC...0x30FF, // Katakana, without ・
                 0x31F0...0x31FF,                  // Small katakana for Ainu
                 0x3099...0x309C,                  // Voicing marks
                 0xFF66...0xFF9F:                  // Half-width katakana
                true
            default:
                false
            }
        }
    }

    /// Whether this is hiragana or katakana.
    public var isKana: Bool {
        isHiragana || isKatakana
    }

    /// Whether this is a kanji or kana.
    public var isJapanese: Bool {
        isKanji || isKana
    }
}
