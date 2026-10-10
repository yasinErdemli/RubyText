import Foundation
@testable import RubyCore
import Testing

/// A few JMdict entries, in the format `Tools/build-dictionary.py` builds.
private let jmdict = Bundle.module
    .url(forResource: "jmdict-sample", withExtension: "sqlite", subdirectory: "Fixtures")
    .flatMap(RubyDictionary.init(url:))

struct RubyDictionaryTests {
    @Test func theSampleOpens() {
        #expect(jmdict != nil)
    }

    private func firstEntry(for markup: String) -> RubyDictionary.Entry? {
        let content = RubyContent.content(for: markup)
        let word = RubyWordInfo.info(for: content.words[0].range, in: content)
        return jmdict?.entries(for: word).first
    }

    @Test func entriesMatchTheReadingShown() {
        #expect(firstEntry(for: "人気の店")?.readings.first == "にんき")
        #expect(firstEntry(for: "{人気|ひとけ}のない道")?.readings.contains("ひとけ") == true)
    }
}
