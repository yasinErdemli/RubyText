@testable import RubyUI
import SwiftUI
import Testing

/// Which characters may start a line, and which paragraphs break before
/// one that may not, as `RubyText` checks once its text is laid out.
@Suite struct RubyLineStartTests {
    @Test(arguments: Array("。、，．」』）】〕〉》”’！？・：；ーぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶゝゞヽヾ々…‥〜％.,!?)]}"))
    func charactersThatMayNotStartALine(_ character: Character) {
        #expect(!RubyLineBreaking.canStartLine(character))
    }

    @Test(arguments: Array("日本語あいうアイウ「『（【〈《“‘AbZ09０９ "))
    func charactersThatMayStartALine(_ character: Character) {
        #expect(RubyLineBreaking.canStartLine(character))
    }

    /// The paragraphs of `lines` that break badly, where `lines` is text
    /// with `|` at each place a line wrapped and `\n` between paragraphs.
    private func broken(_ lines: String) -> Set<Int> {
        var string = ""
        var lineStarts: [(paragraph: Int, offset: Int)] = []
        for (paragraph, text) in lines.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if paragraph > 0 { string += "\n" }
            var offset = 0
            for line in text.split(separator: "|", omittingEmptySubsequences: false) {
                lineStarts.append((paragraph, offset))
                string += line
                offset += line.utf16.count
            }
        }
        return RubyLineBreaking.badlyBrokenParagraphs(in: string, lineStarts: lineStarts)
    }

    /// Breaking between phrases, a phrase wider than the line leaves 。
    /// alone on the next.
    @Test func aLineStartingWithAFullStopIsFound() {
        #expect(broken("アリョーナで|す。よろしく|お願いします|。") == [0])
        #expect(broken("アリョーナです|。よろしく|お願いします。") == [0])
        #expect(broken("森さん|、よろしく|お願いします。") == [0])
    }

    @Test func smallKanaAndTheLongVowelMarkAreFound() {
        #expect(broken("アリ|ョーナです。") == [0])
        #expect(broken("アリョ|ーナです。") == [0])
        #expect(broken("「はい|」と言った。") == [0])
    }

    @Test func linesStartingWellAreLeftAsTheyAre() {
        #expect(broken("アリョーナで|す。よろしく|お願いします。") == [])
        #expect(broken("森さん、|よろしく|お願いします。") == [])
        #expect(broken("アリョーナです。よろしくお願いします。") == [])
    }

    /// Only lines that wrapped count: a paragraph may start with anything.
    @Test func paragraphsMayStartWithAnyCharacter() {
        #expect(broken("はい。\n。。。\n」と言った。") == [])
        #expect(broken("はい、|学生です。\n森さん、|よろしく|お願いします|。") == [1])
        #expect(broken("森さん、よろしく|お願いします|。\n\nはい|、学生です。") == [0, 2])
        // A line separator breaks a line within its paragraph.
        #expect(broken("はい\u{2028}|、学生です。") == [])
    }

    @Test func paragraphsEndWithTheirLineBreak() {
        let string = "春。\n夏。\u{2028}秋。\r\n冬\n"
        let ranges = RubyLineBreaking.paragraphRanges(in: string)
        // \r\n is one character of two UTF-16 code units.
        #expect(ranges == [0..<3, 3..<10, 10..<12, 12..<12])
        #expect(RubyLineBreaking.paragraphRanges(in: "") == [0..<0])
    }

    /// Each run of `text` with its language.
    private func languages(_ text: AttributedString) -> [(String, String?)] {
        text.runs[\.languageIdentifier].map { language, range in (String(text[range].characters), language) }
    }

    /// Paragraphs that broke badly are set to break between characters,
    /// with their line breaks, since the language at a paragraph's end
    /// decides how it breaks.
    @Test func paragraphsBreakBetweenCharactersWhenAsked() {
        var text = AttributedString("一つ。\n二つ。\n三つ。")
        RubyLineBreaking.phrases.setLanguage(of: &text, endings: [], characterBreaking: [1])
        let runs = languages(text)
        #expect(runs.map(\.0) == ["一つ。\n", "二つ。\n", "三つ。"])
        #expect(runs.map(\.1) == ["ja-u-lw-phrase", "ja-u-lb-strict", "ja-u-lw-phrase"])
    }

    /// Breaking anywhere, a paragraph that broke badly no longer keeps its
    /// ending together.
    @Test func endingsGiveWayToCharacterBreaking() {
        var text = AttributedString("一つ。\n二つ。\n三つ。")
        RubyLineBreaking.anywhere.setLanguage(of: &text, endings: [1..<4, 5..<8, 9..<11], characterBreaking: [1])
        let runs = languages(text)
        #expect(runs.map(\.0) == ["一", "つ。\n", "二つ。\n三", "つ。"])
        #expect(runs.map(\.1) == ["ja-u-lb-strict", "ja-u-lw-phrase", "ja-u-lb-strict", "ja-u-lw-phrase"])
    }
}
