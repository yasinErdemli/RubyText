/// Converts kana to romaji, with no dictionary and nothing beyond the
/// standard library.
///
/// Kana alone can't tell whether おう is one long vowel or two (東京 is
/// tōkyō but 思う omou), or whether は is the particle wa: pass a
/// pronunciation where you know it, or use RubyCore, which finds both with
/// its dictionary.
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
        romanize(kana, system: .hepburn, pronunciation: pronunciation)
    }

    /// Text written in kana in `system`: きょうと is kyōto in Hepburn,
    /// kyôto in Nihon-shiki, kyoto in passport style, and 교토 in Hangul.
    ///
    /// Punctuation and kanji are treated as `hepburn(_:pronunciation:)`
    /// treats them.
    public static func romanize(_ kana: String, system: RubyRomanization, pronunciation: String? = nil) -> String {
        system.transliterate(kana, pronunciation: pronunciation)
    }
}
