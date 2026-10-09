/// Japanese to transliterate: the words of a phrase as an analyzer read
/// them, and the morae they're spoken in.
///
/// A phrase is what romaji write as one word: a word with its endings,
/// such as 読んだ (yonda) or 勉強して (benkyō shite is two). RubyCore groups
/// words into phrases; for kana alone, `init(kana:pronunciation:)` makes
/// one.
public struct RubyPhrase: Hashable, Sendable {
    /// A word of a phrase.
    public struct Word: Hashable, Sendable {
        /// What a word does in its sentence, as far as transliteration
        /// cares.
        public enum Role: Hashable, Sendable {
            /// A name of a person or place: styles may capitalize it.
            case properNoun
            /// A particle: は and へ are spoken わ and え.
            case particle
            case other
        }

        /// The word as written: 東京.
        public var surface: String
        /// Its reading in kana: とうきょう.
        public var reading: String
        /// How the reading is spoken, kana for kana, if known: とーきょー
        /// for long vowels, わ for the particle は. Without one, おう, おお
        /// and うう are read as long vowels.
        public var pronunciation: String?
        public var role: Role
        /// Offsets in `reading`, in characters, where a space goes, such
        /// as between the pieces of a long number: にせん|にじゅうろく.
        public var breaks: [Int]

        public init(_ surface: String, reading: String? = nil, pronunciation: String? = nil, role: Role = .other, breaks: [Int] = []) {
            self.surface = surface
            self.reading = reading ?? surface
            self.pronunciation = pronunciation
            self.role = role
            self.breaks = breaks
        }
    }

    public let words: [Word]
    /// The phrase's morae, in order, each knowing which word it's from.
    public let morae: [RubyMora]
    /// The first mora after the phrase, if anything follows it, so a final
    /// っ knows the consonant it doubles: 行っ before た is it.
    public let following: RubyMora?

    /// A phrase of `words`, with `following`, the reading after it, for a
    /// final っ.
    public init(_ words: [Word], following: String? = nil) {
        self.words = words
        morae = words.enumerated().flatMap { RubyMora.morae(of: $1, index: $0) }
        self.following = following.flatMap { RubyMora.morae(of: Word($0), index: 0).first }
    }

    /// Kana with no dictionary, as one word: おう, おお and うう are long
    /// vowels unless `pronunciation` says otherwise.
    public init(kana: String, pronunciation: String? = nil) {
        self.init([Word(kana, pronunciation: pronunciation)])
    }
}

/// A way of writing Japanese in another script, one phrase at a time.
///
/// `RubyTableStyle` covers most systems with data: how each syllable is
/// written, and rules for ん, っ, long vowels and particles. Conform to
/// this protocol for systems a table can't express, as `RubyHangulStyle`
/// does to put ん and っ inside the syllable before them (しんぶん is
/// 신분). The phrase's morae already resolve what kana leave open, such as
/// long vowels and particles, so a style only decides how to write them.
public protocol RubyTransliterationStyle: Hashable, Sendable {
    /// `phrase` written in this style.
    func transliterate(_ phrase: RubyPhrase) -> String
}

/// A system for writing Japanese readings in another script: romaji in
/// one of several systems, Cyrillic, or Hangul.
///
///     RubyText("東京へ行きたい。")
///         .rubyStyle(.romaji)
///         .rubyRomanization(.kunrei)   // Tôkyô e ikitai
///
/// Each wraps a `RubyTransliterationStyle`. Make your own from a
/// `RubyTableStyle` or your own conforming type:
///
///     var style = RubyTableStyle.hepburn
///     style.words["東京"] = "Tokyo"
///     let romanization = RubyRomanization(style)
public struct RubyRomanization: Hashable, Sendable, CaseIterable, CustomStringConvertible {
    /// The style that writes the text.
    public let style: any RubyTransliterationStyle
    // Tables are large, so they're hashed once.
    private let hash: Int

    public init(_ style: some RubyTransliterationStyle) {
        self.style = style
        hash = style.hashValue
    }

    /// `phrase` written in this system.
    public func transliterate(_ phrase: RubyPhrase) -> String {
        style.transliterate(phrase)
    }

    /// Kana written in this system, with no dictionary: おう, おお and うう
    /// are long vowels unless `pronunciation` says otherwise.
    public func transliterate(_ kana: String, pronunciation: String? = nil) -> String {
        style.transliterate(RubyPhrase(kana: kana, pronunciation: pronunciation))
    }

    /// The style's name, such as hepburn.
    public var description: String {
        (style as? any CustomStringConvertible)?.description ?? String(describing: type(of: style))
    }

    public static func == (lhs: RubyRomanization, rhs: RubyRomanization) -> Bool {
        lhs.hash == rhs.hash && lhs.style.isEqual(to: rhs.style)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }

    /// Modified Hepburn, the most widely used: shi, chi, tsu, fu, ji, and
    /// long vowels with macrons (Tōkyō, kōhī), except えい and いい, which
    /// are spelled out (sensei, ii).
    public static let hepburn = RubyRomanization(RubyTableStyle.hepburn)
    /// Kunrei-shiki (ISO 3602), taught in Japanese schools: si, ti, tu,
    /// hu, zi, sya, and long vowels with circumflexes (Tôkyô).
    public static let kunrei = RubyRomanization(RubyTableStyle.kunrei)
    /// Nihon-shiki (ISO 3602 Strict), which follows the kana table: as
    /// Kunrei-shiki, and di, du, dya for ぢ, づ and ぢゃ, wo for を.
    public static let nippon = RubyRomanization(RubyTableStyle.nippon)
    /// Hepburn as Japanese passports write names: long vowels unmarked
    /// (Tokyo, Sato), m before b, m, and p (Namba, Homma), and no
    /// apostrophe after n (Junichi).
    public static let passport = RubyRomanization(RubyTableStyle.passport)
    /// As Japanese is typed: kana for kana, so long vowels are spelled as
    /// written (toukyou, ko-hi-) and particles too (konnichiha).
    public static let wapuro = RubyRomanization(RubyTableStyle.wapuro)
    /// Hepburn for Turkish readers: ş, ç and c for sh, ch and j, long
    /// vowels with circumflexes, and names capitalized as Turkish does
    /// (İbaraki).
    public static let turkish = RubyRomanization(RubyTableStyle.turkish)
    /// Polivanov, the Cyrillic system Russian uses: суси, симбун, самурай.
    public static let polivanov = RubyRomanization(RubyTableStyle.polivanov)
    /// Hangul, as Korean writes Japanese: 도쿄, 삿포로, 신분.
    public static let hangul = RubyRomanization(RubyHangulStyle())

    /// The built-in systems.
    public static let allCases: [RubyRomanization] = [
        .hepburn, .kunrei, .nippon, .passport, .wapuro, .turkish, .polivanov, .hangul,
    ]
}

extension RubyTransliterationStyle {
    /// Whether `other` is this style.
    fileprivate func isEqual(to other: any RubyTransliterationStyle) -> Bool {
        (other as? Self) == self
    }
}
