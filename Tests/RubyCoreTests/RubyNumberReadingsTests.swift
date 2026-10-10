import RubyCore
import RubyMeCab
import Testing

@Suite struct RubyNumberReadingsTests {
    @Test(arguments: [
        (0, "ぜろ"), (1, "いち"), (10, "じゅう"), (11, "じゅういち"), (19, "じゅうきゅう"), (40, "よんじゅう"),
        (100, "ひゃく"), (300, "さんびゃく"), (600, "ろっぴゃく"), (800, "はっぴゃく"),
        (1000, "せん"), (3000, "さんぜん"), (8000, "はっせん"), (10_000, "いちまん"),
        (2026, "にせんにじゅうろく"), (100_000_000, "いちおく"), (1_000_000_000_000, "いっちょう"),
    ])
    func numbers(_ value: Int, _ reading: String) {
        #expect(RubyNumberReadings.reading(of: value) == reading)
    }

    @Test(arguments: [
        // Sound changes at the end of the number.
        (1, "本", "いっぽん"), (3, "本", "さんぼん"), (4, "本", "よんほん"), (6, "本", "ろっぽん"),
        (10, "本", "じゅっぽん"), (21, "本", "にじゅういっぽん"), (100, "本", "ひゃっぽん"), (1000, "本", "せんぼん"),
        (1, "匹", "いっぴき"), (3, "匹", "さんびき"), (1, "杯", "いっぱい"), (3, "杯", "さんばい"),
        (3, "泊", "さんぱく"),
        (1, "分", "いっぷん"), (2, "分", "にふん"), (3, "分", "さんぷん"), (4, "分", "よんぷん"),
        (5, "分", "ごふん"), (10, "分", "じゅっぷん"),
        (1, "回", "いっかい"), (6, "回", "ろっかい"), (3, "回", "さんかい"),
        (3, "階", "さんがい"), (1, "個", "いっこ"), (3, "ヶ月", "さんかげつ"), (6, "か月", "ろっかげつ"),
        (1, "冊", "いっさつ"), (6, "冊", "ろくさつ"), (8, "歳", "はっさい"), (20, "歳", "はたち"),
        (3, "足", "さんぞく"), (1, "週間", "いっしゅうかん"),
        // Special readings of a digit.
        (4, "時", "よじ"), (7, "時", "しちじ"), (9, "時", "くじ"), (14, "時", "じゅうよじ"), (4, "時間", "よじかん"),
        (4, "月", "しがつ"), (7, "月", "しちがつ"), (9, "月", "くがつ"), (12, "月", "じゅうにがつ"),
        (1, "人", "ひとり"), (2, "人", "ふたり"), (4, "人", "よにん"), (11, "人", "じゅういちにん"),
        (4, "年", "よねん"), (4, "円", "よえん"), (4, "枚", "よんまい"),
        (1, "つ", "ひとつ"), (9, "つ", "ここのつ"),
        // Days.
        (2, "日", "ふつか"), (8, "日", "ようか"), (10, "日", "とおか"), (14, "日", "じゅうよっか"),
        (17, "日", "じゅうしちにち"), (19, "日", "じゅうくにち"), (20, "日", "はつか"),
        (24, "日", "にじゅうよっか"), (31, "日", "さんじゅういちにち"),
    ])
    func counters(_ value: Int, _ counter: String, _ reading: String) {
        #expect(RubyNumberReadings.reading(of: value, counter: counter) == reading)
    }

    @Test func firstOfTheMonth() {
        #expect(RubyNumberReadings.reading(of: 1, counter: "日") == "いちにち")
        #expect(RubyNumberReadings.reading(of: 1, counter: "日", afterMonth: true) == "ついたち")
    }

    /// The reading `RubyContent` gives a stretch of text, as base/reading.
    private func segments(_ text: String) -> [String] {
        RubyContent.segments(in: text, analyzer: RubyMeCabAnalyzer.ipadic)
            .map { "\($0.base)/\($0.reading ?? "-")" }
    }

    @Test(arguments: [
        ("2025年3月16日", ["2025年/にせんにじゅうごねん", "3月/さんがつ", "16日/じゅうろくにち"]),
        ("三月一日、", ["三月/さんがつ", "一日/ついたち", "、/-"]),
        ("二〇二六年", ["二〇二六年/にせんにじゅうろくねん"]),
        ("1,000円", ["1,000円/せんえん"]),
        ("１０分", ["１０分/じゅっぷん"]),
        ("3.5キロ", ["3.5/さんてんご", "キロ/きろ"]),
        ("０９０", ["０９０/ぜろきゅうぜろ"]),
        ("何本", ["何本/なんぼん"]),
        ("六日間", ["六日間/むいかかん"]),
        ("十分間", ["十分間/じゅっぷんかん"]),
        // Rough counts: two or three days, four or five people.
        ("二三日", ["二三日/にさんにち"]),
        ("四五人", ["四五人/しごにん"]),
        ("三四本", ["三四本/さんよんほん"]),
        ("五六回", ["五六回/ごろっかい"]),
    ])
    func readsSpans(_ text: String, _ expected: [String]) {
        #expect(segments(text) == expected)
    }

    @Test func numbersAreRuleReadings() {
        let segment = RubyContent.segments(in: "3日", analyzer: RubyMeCabAnalyzer.ipadic).first
        #expect(segment?.source == .rule)
        #expect(segment?.reading == "みっか")
    }

    /// Words that contain numerals, and digits inside codes, keep the
    /// analyzer's segments and readings. Some are phrases, which the
    /// phrase rules mark as theirs (一昨日).
    @Test(arguments: [
        "万歳", "八百屋", "五月雨", "二日酔い", "三日月", "一昨日", "七夕", "千葉", "万一",
        "昨日は十分休んだ。", "三分の一", "第一", "一緒に", "iPhone15", "12:30", "2026/10/08", "090-1234-5678",
    ])
    func leavesWordsAlone(_ text: String) {
        func readings(_ segments: [RubySegment]) -> [String] {
            segments.map { "\($0.base)/\($0.reading ?? "")" }
        }
        let analyzed = RubyMeCabAnalyzer.ipadic.segments(in: text)
        #expect(readings(RubyContent.segments(in: text, analyzer: RubyMeCabAnalyzer.ipadic)) == readings(analyzed))
    }
}
