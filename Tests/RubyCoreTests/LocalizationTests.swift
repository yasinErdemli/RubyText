import Foundation
import RubyCore
import Testing

/// The languages RubyText's own text is translated into, besides English.
let translatedLanguages: Set<String> = [
    "ar", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "pt-BR", "ru", "th", "tr", "vi", "zh-Hans", "zh-Hant",
]

/// The string catalogs of RubyCore and RubyUI, read from the sources.
private let catalogs: [URL] = ["RubyCore", "RubyUI"].map {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/\($0)/Localizable.xcstrings").standardizedFileURL
}

@Suite struct LocalizationTests {
    /// Every string has every translation, with the same placeholders as
    /// English. A language missing a string shows its key, not English.
    @Test(arguments: catalogs)
    func catalogsAreComplete(_ url: URL) throws {
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)
        for (key, string) in strings {
            let localizations = string["localizations"] as? [String: [String: [String: String]]] ?? [:]
            let english = try #require(localizations["en"]?["stringUnit"]?["value"], "\(key) has no English")
            #expect(Set(localizations.keys).subtracting(["en"]) == translatedLanguages, "\(key)")
            for (language, localization) in localizations {
                let value = localization["stringUnit"]?["value"] ?? ""
                #expect(value.components(separatedBy: "%@").count == english.components(separatedBy: "%@").count, "\(key) in \(language)")
            }
        }
    }

    @Test func partOfSpeechNamesAreTranslated() {
        func name(_ partOfSpeech: RubyPartOfSpeech, in language: String) -> String {
            var resource = partOfSpeech.localizedName
            resource.locale = Locale(identifier: language)
            return String(localized: resource)
        }
        #expect(name(.noun, in: "en") == "Noun")
        #expect(name(.noun, in: "ja") == "名詞")
        #expect(name(.particle, in: "ko") == "조사")
        #expect(name(.verb, in: "pt-BR") == "Verbo")
        // Languages without a translation fall back to English.
        #expect(name(.noun, in: "sw") == "Noun")
    }
}
