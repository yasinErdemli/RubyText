import Foundation
@testable import RubyUI
import Testing

/// RubyUI's own text resolves from its bundle, whatever the app's
/// languages.
@Suite struct RubyLocalizationTests {
    private func string(_ resource: LocalizedStringResource, in language: String) -> String {
        var resource = resource
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }

    @Test func wordDetailsAreTranslated() {
        #expect(string(.meaning, in: "en") == "Meaning")
        #expect(string(.meaning, in: "ja") == "意味")
        #expect(string(.meaning, in: "zh-Hans") == "释义")
        #expect(string(.kanji, in: "ar") == "كانجي")
        #expect(string(.jlpt, in: "ja") == "JLPT")
    }

    @Test func argumentsAreFilledIn() {
        #expect(string(.lookUp("食べる"), in: "en") == "Look Up “食べる”")
        #expect(string(.lookUp("食べる"), in: "ja") == "「食べる」を調べる")
        #expect(string(.lookUp("食べる"), in: "de") == "„食べる“ nachschlagen")
        #expect(string(.alsoEntries("生【せい】 life"), in: "fr") == "Aussi : 生【せい】 life")
    }
}
