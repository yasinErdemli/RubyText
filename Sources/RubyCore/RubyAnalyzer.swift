import Foundation

/// Finds words and their readings in Japanese text.
///
/// Putting analysis behind a protocol lets another analyzer, such as a
/// Sudachi-based one, replace or supplement `RubyMeCabAnalyzer` without
/// changing anything that consumes its output.
public protocol RubyAnalyzer: Sendable {
    /// Segments covering all of `text`, in order; joining their `base`
    /// returns `text`.
    func segments(in text: String) -> [RubySegment]
}
