import Foundation
import IPADic
import RubyCore

extension RubyAnalyzer where Self == RubyMeCabAnalyzer {
    /// MeCab with the IPAdic dictionary bundled in this module, about
    /// 50 MB. Loaded the first time it's used, then shared.
    ///
    ///     ContentView()
    ///         .rubyAnalyzer(.ipadic)
    public static var ipadic: RubyMeCabAnalyzer { bundledIPADic }
}

private let bundledIPADic = RubyMeCabAnalyzer(dictionary: IPADic().url)
