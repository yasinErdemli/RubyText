import RubyCore
import RubyIPADic

extension RubyContent {
    /// Content for `markup` analyzed with IPAdic, as most tests expect.
    static func content(for markup: String) -> RubyContent {
        content(for: markup, analyzer: RubyMeCabAnalyzer.ipadic)
    }

    /// Content for `markup` analyzed with IPAdic, with `chooser`'s readings.
    static func content(for markup: String, chooser: some RubyReadingChooser) async -> RubyContent {
        await content(for: markup, analyzer: RubyMeCabAnalyzer.ipadic, chooser: chooser)
    }
}
