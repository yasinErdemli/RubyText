import Foundation

/// Finds words and their readings in Japanese text.
///
/// Putting analysis behind a protocol lets another analyzer, such as a
/// Sudachi-based one, replace or supplement `RubyMeCabAnalyzer` without
/// changing anything that consumes its output.
///
/// Analyzers are `Hashable` so results can be cached per analyzer: two
/// analyzers that compare equal must return the same segments for the same
/// text. A class usually compares by identity.
///
/// Choose one for `RubyText` views with `rubyAnalyzer(_:)`, and pass the
/// same one to `RubyReader` so its spoken phrases line up with the views.
public protocol RubyAnalyzer: Hashable, Sendable {
    /// Segments covering all of `text`, in order; joining their `base`
    /// returns `text`.
    func segments(in text: String) -> [RubySegment]
}
