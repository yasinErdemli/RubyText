import Foundation

/// Parses `{base|reading}` markup, before any analysis runs.
public enum RubyMarkup {
    /// A run of plain text, or text with a manual reading.
    public struct Piece: Hashable, Sendable {
        public let base: String
        public let reading: String?
    }

    /// The text with markup removed: `{漢字|かんじ}を読む` becomes `漢字を読む`.
    public static func plainText(_ markup: String) -> String {
        parse(markup).map(\.base).joined()
    }

    /// Parses inline markup of the form `{漢字|かんじ}を{読|よ}む。`
    ///
    /// Text inside `{base|reading}` becomes a piece with a manual reading,
    /// which overrides the automatic one; everything else is plain text.
    public static func parse(_ markup: String) -> [Piece] {
        let pattern = #/\{([^{}|]+)\|([^{}]*)\}/#
        var pieces: [Piece] = []
        var cursor = markup.startIndex

        for match in markup.matches(of: pattern) {
            if cursor < match.range.lowerBound {
                pieces.append(Piece(base: String(markup[cursor..<match.range.lowerBound]), reading: nil))
            }
            let reading = String(match.output.2)
            pieces.append(Piece(base: String(match.output.1), reading: reading.isEmpty ? nil : reading))
            cursor = match.range.upperBound
        }

        if cursor < markup.endIndex {
            pieces.append(Piece(base: String(markup[cursor...]), reading: nil))
        }
        return pieces
    }
}
