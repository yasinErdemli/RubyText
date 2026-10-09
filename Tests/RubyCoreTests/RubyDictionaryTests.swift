@testable import RubyCore
import RubyJMdict
import Testing

@Suite struct RubyDictionaryTests {
    private func firstEntry(for markup: String) -> RubyDictionary.Entry? {
        let content = RubyContent.content(for: markup)
        let word = RubyWordInfo.info(for: content.words[0].range, in: content)
        return RubyDictionary.jmdict.entries(for: word).first
    }

    @Test func entriesMatchTheReadingShown() {
        #expect(firstEntry(for: "人気の店")?.readings.first == "にんき")
        #expect(firstEntry(for: "{人気|ひとけ}のない道")?.readings.contains("ひとけ") == true)
    }
}
