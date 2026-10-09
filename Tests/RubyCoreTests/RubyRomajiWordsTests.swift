@testable import RubyCore
import Testing

/// Romaji as RubyCore groups it, with readings and word roles from its
/// dictionary.
@Suite struct RubyRomajiWordsTests {
    /// Romaji words for whole sentences, as shown below the text.
    @Test(arguments: [
        ("今日は東京へ行きたい。", "kyō wa tōkyō e ikitai"),
        ("コーヒーを飲みながら日本語を勉強しています。", "kōhī o nominagara nihongo o benkyō shite imasu"),
        ("漫画を読んだ。", "manga o yonda"),
        ("気に入った店", "kiniitta mise"),
        ("東京で会おう。", "tōkyō de aō"),
        ("学校では静かだ。", "gakkō dewa shizuka da"),
        ("映画でも見ましょう。", "eiga demo mimashō"),
        ("食べてしまった。", "tabete shimatta"),
        ("先生です。", "sensei desu"),
        ("吾輩は猫である。", "wagahai wa neko de aru"),
        ("湖を追う。", "mizuumi o ou"),
    ])
    func romajiWords(_ text: String, _ expected: String) {
        let content = RubyContent.content(for: text)
        #expect(content.romajiWords.map(\.text).joined(separator: " ") == expected)
    }

    @Test(arguments: [
        ("十日", "tōka"),
        ("2026年", "nisen nijūrokunen"),
        ("3500円", "sanzen gohyakuen"),
        ("六百人", "roppyakunin"),
        ("1,234,567", "hyaku nijūsanman yonsen gohyaku rokujūnana"),
        ("100", "hyaku"),
    ])
    func numbersReadInParts(_ text: String, _ expected: String) {
        let content = RubyContent.content(for: text)
        let romaji = content.romajiWords.map(\.text).joined(separator: " ")
        #expect(romaji == expected, "\(romaji)")
    }
}
