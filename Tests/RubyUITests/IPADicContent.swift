import IPADic
import RubyCore

extension RubyMeCabAnalyzer {
    /// MeCab with IPAdic, from the Mecab-Swift package. Apps bundle their
    /// own copy; the tests read with this one.
    static let ipadic = RubyMeCabAnalyzer(dictionary: IPADic().url)
}

extension RubyContent {
    /// Content for `markup` analyzed with IPAdic, as the tests expect.
    static func content(for markup: String) -> RubyContent {
        content(for: markup, analyzer: RubyMeCabAnalyzer.ipadic)
    }
}
