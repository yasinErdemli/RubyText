import Foundation
@testable import RubyCore
import Testing

/// The demo app's database. The library doesn't include one, so these
/// tests are skipped without it.
private let jmdict = RubyDictionary(url: URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../../../Untitled Project/Dictionary/jmdict.sqlite")
    .standardized)

@Suite(.enabled(if: jmdict != nil, "The demo app's JMdict isn't there"))
struct RubyDictionaryTests {
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
