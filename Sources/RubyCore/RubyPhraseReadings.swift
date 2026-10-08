import Foundation

/// The rule layer for fixed phrases, and for 中 after a word.
///
/// Fixed phrases run before the number rules, so idioms with numerals keep
/// their own readings: 一足先 is ひとあしさき, not one pair of shoes. The 中
/// rule runs after them, since 一日中 needs 一日 read first.
package enum RubyPhraseReadings {
    /// `segments` with the built-in phrases read as a whole.
    package static func applyPhrases(to segments: [RubySegment]) -> [RubySegment] {
        RubyRuleSpans.replacing(segments) { text, start, isEnd in
            let rest = text[start...]
            for (phrase, reading) in phrases where rest.starts(with: phrase) && isEnd(start + phrase.count) {
                return RubyRuleSpans.Match(end: start + phrase.count, reading: reading)
            }
            return nil
        }
    }

    /// `segments` with 中 after a word read じゅう or ちゅう where the word
    /// decides it.
    ///
    /// After a stretch of time or a place, 中 means "throughout" and reads
    /// じゅう: 一日中, 今年中, 世界中, 体中. After an activity it means "in
    /// the middle of" and reads ちゅう (会議中), as do a few time words:
    /// 午前中, 今週中. Words not listed keep the analyzer's reading, since
    /// 中 also reads なか (箱の中).
    package static func applySuffixes(to segments: [RubySegment]) -> [RubySegment] {
        var result = segments
        for index in result.indices.dropFirst() where result[index].base == "中" && result[index].source == .dictionary {
            let previous = result[index - 1]
            let reading: String
            if throughoutWords.contains(previous.base) {
                reading = "じゅう"
            } else if duringWords.contains(previous.base) {
                reading = "ちゅう"
            } else {
                continue
            }
            result[index].reading = reading
            result[index].source = .rule
        }
        return result
    }

    /// Words after which 中 reads じゅう, "throughout".
    private static let throughoutWords: Set<String> = [
        // Time.
        "一日", "一年", "一晩", "今日", "今年", "明日", "今夜",
        // Places and wholes.
        "世界", "日本", "国", "家", "体", "部屋", "学校", "会社", "村", "島", "県",
    ]

    /// Time words after which 中 reads ちゅう, "during".
    private static let duringWords: Set<String> = ["午前", "午後", "今週", "来週", "今月", "来月", "期間"]

    /// Phrases read as a whole, longest first so they win over phrases they
    /// contain.
    private static let phrases: [(String, String)] = [
        ("一枚上手", "いちまいうわて"),
        ("七転八倒", "しちてんばっとう"),
        ("一足早く", "ひとあしはやく"),
        ("一足先", "ひとあしさき"),
        ("一通り", "ひととおり"),
        ("一晩", "ひとばん"),
        ("国中", "くにじゅう"),
    ].sorted { $0.0.count > $1.0.count }
}
