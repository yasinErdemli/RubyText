import Foundation

/// The rule layer for fixed phrases, 中 after a word, and 何 before one.
///
/// Fixed phrases run before the number rules, so idioms with numerals keep
/// their own readings: 一足先 is ひとあしさき, not one pair of shoes. The 中
/// rule runs after them, since 一日中 needs 一日 read first.
package enum RubyPhraseReadings {
    /// `segments` with the built-in phrases read as a whole. Phrases the
    /// analyzer already reads right keep its words and grammar.
    package static func applyPhrases(to segments: [RubySegment]) -> [RubySegment] {
        RubyRuleSpans.replacing(segments) { text, start, isEnd in
            let rest = text[start...]
            for (phrase, reading) in phrases where rest.starts(with: phrase) && isEnd(start + phrase.count) {
                return RubyRuleSpans.Match(end: start + phrase.count, reading: reading)
            }
            return nil
        } keeping: { covered, reading in
            covered.map { $0.reading ?? $0.base }.joined() == reading
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
                // The word before reads as it does with じゅう: 今日 is きょう
                // in 今日中, not こんにち.
                if let before = throughoutReadings[previous.base], previous.source == .dictionary, previous.reading != before {
                    result[index - 1].reading = before
                    result[index - 1].pronunciation = nil
                    result[index - 1].source = .rule
                }
            } else if duringWords.contains(previous.base) {
                reading = "ちゅう"
            } else {
                continue
            }
            guard result[index].reading != reading else { continue }
            result[index].reading = reading
            result[index].pronunciation = nil
            result[index].source = .rule
        }
        return result
    }

    /// `segments` with 何 read なん where なに shortens before the word
    /// after it: before だ, で, の, と, て, な and じゃ (何ですか, 何の, 何と,
    /// 何でも), and なに before を, が, も, か and に (何を, 何か), where
    /// analyzers read it otherwise.
    ///
    /// Elsewhere the analyzer's reading stays, such as なん before
    /// counters (何人).
    package static func applyNan(to segments: [RubySegment]) -> [RubySegment] {
        var result = segments
        for index in result.indices.dropLast() where result[index].base == "何" && result[index].source == .dictionary {
            let next = result[index + 1].base
            let reading: String
            if nanBefore.contains(where: next.hasPrefix) {
                reading = "なん"
            } else if naniBefore.contains(next) {
                reading = "なに"
            } else {
                continue
            }
            guard result[index].reading != reading else { continue }
            result[index].reading = reading
            result[index].pronunciation = nil
            result[index].source = .rule
        }
        return result
    }

    /// `segments` with 日本 read にほん, as most people say it and learners
    /// are taught, where the analyzer reads it にっぽん, as IPAdic and
    /// UniDic both do: 日本, 日本人. Names that are read にっぽん keep it:
    /// 日本銀行, 日本郵便.
    package static func applyNihon(to segments: [RubySegment]) -> [RubySegment] {
        var result = segments
        for index in result.indices where result[index].source == .dictionary {
            let segment = result[index]
            guard segment.base.hasPrefix("日本"), let reading = segment.reading, reading.hasPrefix("にっぽん") else { continue }
            // The rest of the name, in this word or the next.
            let rest = segment.base.dropFirst(2) + (index + 1 < result.count ? result[index + 1].base : "")
            guard !nipponNames.contains(where: rest.hasPrefix) else { continue }
            result[index].reading = "にほん" + reading.dropFirst(4)
            result[index].pronunciation = nil
            result[index].source = .rule
        }
        return result
    }

    /// Words after 日本 in names that read it にっぽん.
    private static let nipponNames = ["銀行", "放送協会", "武道館", "郵便", "製鉄", "通運"]

    /// Kana that 何 reads なん before.
    private static let nanBefore = ["だ", "で", "の", "と", "て", "な", "じゃ"]

    /// Particles that 何 reads なに before.
    private static let naniBefore: Set<String> = ["を", "が", "も", "か", "に"]

    /// Words after which 中 reads じゅう, "throughout".
    private static let throughoutWords: Set<String> = [
        // Time, as the number rules leave it (1日) or the analyzer does.
        "一日", "1日", "１日", "一年", "1年", "１年", "一晩", "今日", "今年", "明日", "今夜",
        // Places and wholes.
        "世界", "日本", "国", "家", "体", "部屋", "学校", "会社", "村", "島", "県",
    ]

    /// How words before じゅう read where analyzers may read them otherwise.
    private static let throughoutReadings: [String: String] = ["今日": "きょう", "体": "からだ"]

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
        // Analyzers split 振り|仮名 and read 仮名 かめい, "pseudonym".
        ("振り仮名", "ふりがな"),
        ("振仮名", "ふりがな"),
        ("一晩", "ひとばん"),
        ("国中", "くにじゅう"),
        ("百人一首", "ひゃくにんいっしゅ"),
        // 分 as a tenth, in sayings: not minutes or a fraction.
        ("一分の隙", "いちぶのすき"),
        ("五分の魂", "ごぶのたましい"),
        ("五分五分", "ごぶごぶ"),
        ("九分九厘", "くぶくりん"),
        // Four-character idioms, which analyzers that split them into
        // short words read kanji by kanji.
        ("十人十色", "じゅうにんといろ"),
        ("一期一会", "いちごいちえ"),
        ("四六時中", "しろくじちゅう"),
        // Family, which analyzers that split off さん read as written: は
        // は for 母.
        ("お母さん", "おかあさん"),
        ("お父さん", "おとうさん"),
        ("お兄さん", "おにいさん"),
        ("お姉さん", "おねえさん"),
        ("母さん", "かあさん"),
        ("父さん", "とうさん"),
        ("兄さん", "にいさん"),
        ("姉さん", "ねえさん"),
        // Words read as a whole, which some analyzers read kanji by kanji.
        ("一昨日", "おととい"),
        ("一昨年", "おととし"),
        ("意気地", "いくじ"),
        ("時々", "ときどき"),
        ("魚市場", "うおいちば"),
        ("富士山", "ふじさん"),
        // 入る reads いる in 気に入る, which some analyzers read はいる.
        ("気に入る", "きにいる"),
        ("気に入り", "きにいり"),
        ("気に入っ", "きにいっ"),
        ("気に入ら", "きにいら"),
        ("気に入れ", "きにいれ"),
    ].sorted { $0.0.count > $1.0.count }
}
