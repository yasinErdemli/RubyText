import RubyCore
import SwiftUI

/// How `RubyText` emphasizes the word a `RubyReader` is speaking.
///
/// Combine effects as a set:
///
///     RubyText("吾輩は猫である。")
///         .rubyReader(reader)
///         .rubyEmphasis([.tint, .grow])
public struct RubyEmphasis: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Colors the word, and its annotations, with the tint color.
    public static let tint = RubyEmphasis(rawValue: 1 << 0)
    /// Draws a soft tinted background behind the word.
    public static let highlight = RubyEmphasis(rawValue: 1 << 1)
    /// Scales the word up slightly.
    public static let grow = RubyEmphasis(rawValue: 1 << 2)
    /// Sweeps the tint color across the word as it's spoken.
    public static let karaoke = RubyEmphasis(rawValue: 1 << 3)

    public static let all: RubyEmphasis = [.tint, .highlight, .grow, .karaoke]
}

extension EnvironmentValues {
    /// How `RubyText` emphasizes the spoken word. Tint and grow by default.
    @Entry var rubyEmphasis: RubyEmphasis = [.tint, .grow]
    /// The reader whose spoken words `RubyText` emphasizes, if any.
    @Entry var rubyReader: RubyReader? = nil
}

extension View {
    /// Sets how `RubyText` views in this hierarchy emphasize the spoken word.
    public func rubyEmphasis(_ emphasis: RubyEmphasis) -> some View {
        environment(\.rubyEmphasis, emphasis)
    }

    /// Emphasizes the words `reader` speaks in `RubyText` views showing the
    /// same text.
    public func rubyReader(_ reader: RubyReader?) -> some View {
        environment(\.rubyReader, reader)
    }
}
