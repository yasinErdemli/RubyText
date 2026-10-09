import RubyCore
import RubyIPADic

extension RubyContent {
    /// Content for `markup` analyzed with IPAdic, as the tests expect.
    static func content(for markup: String) -> RubyContent {
        content(for: markup, analyzer: RubyMeCabAnalyzer.ipadic)
    }
}
