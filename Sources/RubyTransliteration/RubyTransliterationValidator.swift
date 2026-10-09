/// Checks a transliteration style against every mora and a shared list of
/// words styles often get wrong, for anything it leaves as kana or can't
/// write.
///
///     #expect(RubyTransliterationValidator.validate(myStyle).isEmpty)
///
/// It can't know how a style should write each word, only that it writes
/// all of them: test the spellings you care about yourself.
public enum RubyTransliterationValidator {
    /// Something a style didn't write.
    public struct Issue: Hashable, Sendable, CustomStringConvertible {
        /// The kana given to the style.
        public let input: String
        /// What the style wrote.
        public let output: String
        /// What's wrong with it.
        public let problem: String

        public var description: String { "\(input) → “\(output)”: \(problem)" }
    }

    /// The phrases a style is checked against: each syllable on its own,
    /// after っ, after ん, and held long, then `trickyWords`.
    public static var phrases: [RubyPhrase] {
        let syllables = RubyMora.syllables.flatMap { kana in
            [kana, "っ" + kana, "ん" + kana, kana + "ー"].map { RubyPhrase(kana: $0) }
        }
        return syllables + trickyWords
    }

    /// Words with the cases styles most often get wrong: long vowels
    /// that are and aren't (とうきょう, おもう), っ and ん before each kind
    /// of sound, particles, kana from other languages, repeat marks,
    /// half-width kana, and punctuation.
    public static let trickyWords: [RubyPhrase] = [
        RubyPhrase(kana: "とうきょう", pronunciation: "とーきょー"),
        RubyPhrase(kana: "せんせい", pronunciation: "せんせー"),
        RubyPhrase(kana: "みずうみ", pronunciation: "みずうみ"),
        RubyPhrase(kana: "おもう", pronunciation: "おもう"),
        RubyPhrase(kana: "おおきい", pronunciation: "おーきい"),
        RubyPhrase(kana: "まっちゃ"),
        RubyPhrase(kana: "さっぽろ"),
        RubyPhrase([.init("行っ", reading: "いっ")], following: "た"),
        RubyPhrase(kana: "あっ"),
        RubyPhrase(kana: "げんいん"),
        RubyPhrase(kana: "きんようび", pronunciation: "きんよーび"),
        RubyPhrase(kana: "しんぶん"),
        RubyPhrase(kana: "こんにちは", pronunciation: "こんにちわ"),
        RubyPhrase([.init("は", role: .particle)]),
        RubyPhrase([.init("へ", role: .particle)]),
        RubyPhrase([.init("を", role: .particle)]),
        RubyPhrase(kana: "ファイル"),
        RubyPhrase(kana: "ティッシュ"),
        RubyPhrase(kana: "ヴァイオリン"),
        RubyPhrase(kana: "ウィキ"),
        RubyPhrase(kana: "チェック"),
        RubyPhrase(kana: "ツァー"),
        RubyPhrase(kana: "はなぢ"),
        RubyPhrase(kana: "つづく"),
        RubyPhrase(kana: "いすゞ"),
        RubyPhrase(kana: "こゝろ"),
        RubyPhrase(kana: "ねぇ"),
        RubyPhrase(kana: "すごーい"),
        RubyPhrase(kana: "ｶﾞｯｺｳ"),
        RubyPhrase(kana: "ゐる"),
        RubyPhrase(kana: "ジョン・スミス"),
        RubyPhrase(kana: "「はい」といった。"),
        RubyPhrase([.init("東京", reading: "とうきょう", pronunciation: "とーきょー", role: .properNoun)]),
        RubyPhrase([.init("2026", reading: "にせんにじゅうろく", breaks: [3])]),
    ]

    /// What `style` gets wrong among `phrases`: kana it leaves in its text,
    /// and phrases it writes nothing for.
    public static func validate(_ style: some RubyTransliterationStyle) -> [Issue] {
        phrases.compactMap { phrase in
            let input = phrase.words.map(\.reading).joined()
            let output = style.transliterate(phrase)
            if output.isEmpty, phrase.morae.contains(where: { $0.kind == .syllable }) {
                return Issue(input: input, output: output, problem: "nothing written")
            }
            if let kana = output.first(where: \.isKana) {
                return Issue(input: input, output: output, problem: "\(kana) left as kana")
            }
            return nil
        }
    }
}
