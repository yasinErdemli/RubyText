import Foundation
import RubyTransliteration

/// Japanese text with readings you give in code, written with string
/// interpolation:
///
///     RubyText("\("今日", reading: "きょう")は\(user.name)さんと話した。")
///
/// - Text you write in the literal can use `{base|reading}` markup.
/// - `\(base, reading:)` gives `base` a reading, or leaves it to analysis
///   when the reading is `nil`.
/// - `\(text)` adds a string or a number as text to analyze. Markup in it
///   is shown as written, so text from people using your app can't add
///   readings.
/// - `\(unannotated:)` adds text that's never annotated, such as a
///   product name.
/// - `\(value)` adds anything `RubyStringConvertible`, such as
///   `PersonNameComponents`, read with its phonetic name.
///
/// The pieces are analyzed together, as one text, so words and phrases
/// read across them, and readings you give always win.
///
/// As `Text` treats Markdown, markup only counts where you opt in: in a
/// literal, or in text you load at run time, such as from JSON, with
/// `init(markup:)` or `RubyText(markup:)`. A `String` passed where a
/// `RubyString` is expected is shown as written.
public struct RubyString: Hashable, Sendable, ExpressibleByStringInterpolation, RubyStringConvertible {
    package enum Piece: Hashable, Sendable {
        /// Text with `{base|reading}` markup.
        case markup(String)
        /// Text to analyze, without markup.
        case text(String)
        /// Text with a reading you gave.
        case ruby(base: String, reading: String)
        /// Text that's never annotated.
        case unannotated(String)
    }

    package private(set) var pieces: [Piece]

    /// An empty string.
    public init() {
        pieces = []
    }

    public init(stringLiteral value: String) {
        pieces = value.isEmpty ? [] : [.markup(value)]
    }

    public init(stringInterpolation: StringInterpolation) {
        pieces = stringInterpolation.pieces
    }

    /// Text with `{base|reading}` markup, such as text you load at run
    /// time.
    public init(markup: String) {
        pieces = markup.isEmpty ? [] : [.markup(markup)]
    }

    /// Text that's never annotated, such as a product name.
    public init(unannotated text: String) {
        pieces = text.isEmpty ? [] : [.unannotated(text)]
    }

    /// Text to analyze, shown as written: markup in it isn't read.
    package init(text: String) {
        pieces = text.isEmpty ? [] : [.text(text)]
    }

    /// The text without readings or markup.
    public var plainText: String {
        pieces.map { piece in
            switch piece {
            case .markup(let markup): RubyMarkup.plainText(markup)
            case .text(let text), .unannotated(let text): text
            case .ruby(let base, _): base
            }
        }.joined()
    }

    public var rubyString: RubyString { self }

    public static func + (lhs: RubyString, rhs: RubyString) -> RubyString {
        var result = lhs
        result += rhs
        return result
    }

    public static func += (lhs: inout RubyString, rhs: RubyString) {
        lhs.pieces += rhs.pieces
    }

    /// Collects the pieces of a `RubyString` literal.
    public struct StringInterpolation: StringInterpolationProtocol {
        var pieces: [Piece] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            pieces.reserveCapacity(interpolationCount * 2 + 1)
        }

        /// Text you wrote, which can use `{base|reading}` markup.
        public mutating func appendLiteral(_ literal: String) {
            if !literal.isEmpty { pieces.append(.markup(literal)) }
        }

        /// Text to analyze. Markup in it is shown as written.
        public mutating func appendInterpolation(_ text: some StringProtocol) {
            if !text.isEmpty { pieces.append(.text(String(text))) }
        }

        /// A number, such as 3 in "\(3)日", read with the words around it
        /// (みっか).
        public mutating func appendInterpolation(_ number: some Numeric & CustomStringConvertible) {
            pieces.append(.text(number.description))
        }

        /// `base` with `reading` as its reading, or read by analysis if the
        /// reading is `nil` or empty.
        public mutating func appendInterpolation(_ base: some StringProtocol, reading: String?) {
            guard !base.isEmpty else { return }
            if let reading, !reading.isEmpty {
                pieces.append(.ruby(base: String(base), reading: reading))
            } else {
                pieces.append(.text(String(base)))
            }
        }

        /// Text that's never annotated, such as a product name.
        public mutating func appendInterpolation(unannotated text: some StringProtocol) {
            if !text.isEmpty { pieces.append(.unannotated(String(text))) }
        }

        /// `value` as a `RubyString`, with the readings it gives.
        public mutating func appendInterpolation(_ value: some RubyStringConvertible) {
            pieces += value.rubyString.pieces
        }
    }
}

/// A value with Japanese text and readings to show in `RubyText`, such as a
/// person or a place in your model:
///
///     struct User: RubyStringConvertible {
///         var familyName = "田中", givenName = "花子"
///         var familyKana: String? = "たなか", givenKana: String? = "はなこ"
///
///         var rubyString: RubyString {
///             "\(familyName, reading: familyKana)\(givenName, reading: givenKana)"
///         }
///     }
///
///     RubyText("\(user)さんと話した。")
///
/// Conforming types don't need to be `Sendable`, so main-actor models can
/// conform.
public protocol RubyStringConvertible {
    var rubyString: RubyString { get }
}

extension PersonNameComponents: RubyStringConvertible {
    /// The name with its phonetic representation as readings, in hiragana:
    /// 田中 (たなか) 花子 (はなこ), family name first.
    public var rubyString: RubyString {
        rubyString(readings: .hiragana)
    }

    /// The name with its phonetic representation as readings in `kana`:
    /// hiragana, or katakana, as phonetic names are often written.
    ///
    /// Names written in Japanese put the family name first with no space
    /// between. Names in other scripts read as they're formatted for the
    /// current locale.
    public func rubyString(readings kana: RubyScript.Kana) -> RubyString {
        let parts = [(familyName, phoneticRepresentation?.familyName), (givenName, phoneticRepresentation?.givenName)]
        let written = parts.compactMap(\.0).joined()
        guard !written.isEmpty, written.allSatisfy(RubyKana.isJapanese) else {
            return "\(formatted())"
        }
        var string = RubyString()
        for case let (name?, reading) in parts {
            let shown = reading.map { kana == .hiragana ? RubyKana.hiragana($0) : RubyKana.katakana($0) }
            string += "\(name, reading: shown)"
        }
        return string
    }
}
