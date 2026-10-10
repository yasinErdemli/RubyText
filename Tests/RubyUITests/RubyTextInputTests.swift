import RubyCore
import RubyMeCab
@testable import RubyUI
import SwiftUI
import Testing

/// What `RubyText` reads from what it's given, and what it shows by
/// default.
@MainActor @Suite struct RubyTextInputTests {
    /// The string a `RubyText` was created with.
    private func string(of text: RubyText) -> RubyString? {
        Mirror(reflecting: text).descendant("input", "string") as? RubyString
    }

    /// As `Text` reads Markdown: markup counts in literals and where it's
    /// asked for, and a `String` shows as written.
    @Test func markupIsOnlyReadWhereAskedFor() {
        let typed = "{悪|わる}い"
        #expect(string(of: RubyText("{悪|わる}い")) == RubyString(markup: typed))
        #expect(string(of: RubyText(markup: typed)) == RubyString(markup: typed))
        #expect(string(of: RubyText(typed)) == RubyString(text: typed))
        #expect(string(of: RubyText(typed[...])) == RubyString(text: typed))
        #expect(string(of: RubyText(verbatim: "{悪|わる}い")) == RubyString(text: typed))
    }

    @Test func furiganaShowByDefault() {
        #expect(EnvironmentValues().rubyStyle == .furigana)
    }

    @Test func readersTakeTheirViewsSettings() {
        let reader = RubyReader()
        #expect(reader.analyzer == nil)
        reader.adopt(analyzer: RubyMeCabAnalyzer.ipadic, spokenReadings: .all)
        #expect(reader.analyzer as? RubyMeCabAnalyzer == RubyMeCabAnalyzer.ipadic)
        #expect(reader.spokenReadings == .all)
        // A view without an analyzer leaves the reader's.
        reader.adopt(analyzer: nil, spokenReadings: .corrections)
        #expect(reader.analyzer != nil)
        #expect(reader.spokenReadings == .corrections)
    }
}
