import Foundation
import RubyTransliteration

/// The rule layer for numbers: reads dates, times, amounts, and counted
/// things, which the dictionary reads digit by digit or not at all.
///
/// Runs after an analyzer and replaces the segments that make up a number
/// and its counter with one segment whose reading is computed:
/// 3日 → みっか, 六百人 → ろっぴゃくにん, 2026年 → にせんにじゅうろくねん.
/// The reading covers the whole span, since みっか can't be split between
/// 3 and 日.
///
/// Kanji numerals are only read with a counter, and a span must start and
/// end on the analyzer's word boundaries, so words that merely contain
/// numerals keep the dictionary's reading: 万歳, 八百屋, 五月雨, 三日月.
package enum RubyNumberReadings {
    /// `segments` with each number, and the counter after it, read by rule.
    package static func apply(to segments: [RubySegment]) -> [RubySegment] {
        RubyRuleSpans.replacing(segments, match: match)
    }

    /// The reading of a number with an optional counter, such as 3 and 日,
    /// or `nil` if there's no rule for it.
    package static func reading(of value: Int, counter: String? = nil, afterMonth: Bool = false) -> String? {
        let spoken = Spoken(value)
        guard let counter else { return spoken.text }
        guard let rule = counters.first(where: { $0.spellings.contains(counter) }) else { return nil }
        return rule.read(spoken, value: value, afterMonth: afterMonth)
    }

    // MARK: Matching

    /// A number starting at `start`, with the longest counter after it
    /// whose end `isBoundary` accepts.
    private static func match(in text: [Character], at start: Int, endingAt isBoundary: (Int) -> Bool) -> RubyRuleSpans.Match? {
        guard let number = parseNumber(in: text, at: start) else { return nil }

        // Any counter can take 間 for a span of time (六日間, 十分間), which
        // analyzers often join to the counter as one word.
        let rest = text[number.end...]
        let candidates = counters
            .flatMap { rule in rule.spellings.flatMap { [(rule, $0, ""), (rule, $0 + "間", "かん")] } }
            .filter { rest.starts(with: $0.1) }
            .sorted { $0.1.count > $1.1.count }

        for (rule, spelling, suffix) in candidates {
            let end = number.end + spelling.count
            guard isBoundary(end) else { continue }
            // Context checks look right after the counter itself.
            let counterEnd = suffix.isEmpty ? end : end - 1
            if let reading = reading(of: number, counter: rule, in: text, end: counterEnd) {
                return RubyRuleSpans.Match(end: end, reading: reading + suffix, romajiBreaks: breaks(of: number, in: reading))
            }
        }
        // Kanji numerals without a counter are usually part of a word (第一,
        // 一緒, 万一); digits are always numbers.
        guard number.isDigits, isBoundary(number.end) else { return nil }
        let reading = number.spoken.text
        return RubyRuleSpans.Match(end: number.end, reading: reading, romajiBreaks: breaks(of: number, in: reading))
    }

    /// Where romaji split a number's reading: after each thousand, hundred,
    /// and power of ten thousand that something follows, so 2026 is nisen
    /// nijūroku. Only where the reading still starts with those pieces;
    /// counters can change the end (二十日, はつか).
    private static func breaks(of number: ParsedNumber, in reading: String) -> [Int] {
        var breaks: [Int] = []
        var offset = 0
        let pieces = number.spoken.pieces
        for (index, piece) in pieces.enumerated() {
            offset += piece.count
            guard index < pieces.count - 1, Spoken.magnitudes.contains(piece) else { continue }
            if reading.hasPrefix(pieces[...index].joined()) { breaks.append(offset) }
        }
        return breaks
    }

    private static func reading(of number: ParsedNumber, counter rule: Counter, in text: [Character], end: Int) -> String? {
        if let rough = number.rough {
            // Both numbers, with the counter as it is after the second,
            // but none of the readings for whole numbers: にさんにち, not
            // にみっか; しごにん.
            let second = Spoken(rough.second)
            let counted = rule.kana == "にち" ? second.text + "にち" : rule.read(second, value: -1, afterMonth: false)
            return counted.map { roughKana[rough.first]! + $0 }
        }
        guard let value = number.value else {
            // A decimal, or digits with leading zeros: no sound changes.
            return number.spoken.text + rule.kana
        }
        let previous = number.start > 0 ? text[number.start - 1] : nil
        let following = String(text[end..<min(end + 3, text.count)])

        if rule.kana == "ふん" {
            // 三分の一 is a fraction.
            if following.hasPrefix("の") { return number.spoken.text + "ぶん" }
            // 十分 in kanji usually means "enough"; read it as minutes only
            // where the context says so: 十分後, 十分間, 三時十分.
            if !number.isDigits, value == 10, number.text == "十",
               previous != "時", !minuteContext.contains(where: following.hasPrefix) {
                return nil
            }
        }
        // 1日 is ついたち as a date (三月一日, 毎月1日), いちにち as a duration.
        let afterMonth = previous == "月"
        return rule.read(number.spoken, value: value, afterMonth: afterMonth)
    }

    /// Words after 十分 that show it's ten minutes.
    private static let minuteContext = ["後", "間", "前", "以内", "以上", "以下", "程", "ほど", "おき", "毎", "くらい", "ぐらい", "経"]

    // MARK: Parsing

    private struct ParsedNumber {
        let start: Int
        let end: Int
        let text: String
        /// `nil` for decimals and digit strings with leading zeros.
        let value: Int?
        let spoken: Spoken
        let isDigits: Bool
        /// For a rough count such as 二三 (two or three), the two numbers.
        var rough: (first: Int, second: Int)? = nil
    }

    /// How the first number of a rough count reads: し in 四五人.
    private static let roughKana = [1: "いち", 2: "に", 3: "さん", 4: "し", 5: "ご", 6: "ろく", 7: "しち", 8: "はち"]

    private static let kanjiDigits: [Character: Int] = [
        "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let kanjiMultipliers: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let kanjiGroups: [Character: Int] = ["万": 10_000, "億": 100_000_000, "兆": 1_000_000_000_000]

    private static func parseNumber(in text: [Character], at start: Int) -> ParsedNumber? {
        guard start < text.count else { return nil }
        if digitValue(text[start]) != nil {
            return parseDigits(in: text, at: start)
        }
        if text[start] == "何" {
            return ParsedNumber(start: start, end: start + 1, text: "何", value: -1, spoken: Spoken(pieces: ["なん"]), isDigits: false)
        }
        return parseKanji(in: text, at: start)
    }

    private static func digitValue(_ character: Character) -> Int? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 0x30...0x39: return Int(scalar.value - 0x30)
        case 0xFF10...0xFF19: return Int(scalar.value - 0xFF10)
        default: return nil
        }
    }

    private static func isLatinLetter(_ character: Character) -> Bool {
        character.isLetter && !character.isJapanese
    }

    /// Digits, with optional thousands separators and decimals: 2026,
    /// １０, 1,000, 3.5. Digits inside codes (iPhone15, 12:30, 2026/10/08,
    /// 090-1234) are left alone.
    private static func parseDigits(in text: [Character], at start: Int) -> ParsedNumber? {
        if start > 0, isLatinLetter(text[start - 1]) || ":/-.：／－".contains(text[start - 1]) { return nil }

        var digits: [Int] = []
        var end = start
        while end < text.count, let digit = digitValue(text[end]) {
            digits.append(digit)
            end += 1
        }
        // Thousands separators: exactly three digits after each comma.
        while end + 3 < text.count, ",，".contains(text[end]),
              (1...3).allSatisfy({ digitValue(text[end + $0]) != nil }),
              end + 4 == text.count || digitValue(text[end + 4]) == nil {
            digits += (1...3).map { digitValue(text[end + $0])! }
            end += 4
        }
        var decimals: [Int] = []
        if end + 1 < text.count, ".．".contains(text[end]), digitValue(text[end + 1]) != nil {
            end += 1
            while end < text.count, let digit = digitValue(text[end]) {
                decimals.append(digit)
                end += 1
            }
        }
        if end < text.count, ":/-：／－".contains(text[end]) { return nil }

        let string = String(text[start..<end])
        guard digits.count <= 16 else { return nil }
        let integer = digits.reduce(0) { $0 * 10 + $1 }

        if !decimals.isEmpty {
            let whole = integer == 0 ? "れい" : Spoken(integer).text
            let fraction = decimals.map { $0 == 0 ? "ぜろ" : Spoken.digitKana[$0] }.joined()
            return ParsedNumber(start: start, end: end, text: string, value: nil, spoken: Spoken(pieces: [whole, "てん", fraction]), isDigits: true)
        }
        if digits.count > 1, digits.first == 0 {
            let pieces = digits.map { $0 == 0 ? "ぜろ" : Spoken.digitKana[$0] }
            return ParsedNumber(start: start, end: end, text: string, value: nil, spoken: Spoken(pieces: pieces), isDigits: true)
        }
        return ParsedNumber(start: start, end: end, text: string, value: integer, spoken: Spoken(integer), isDigits: true)
    }

    /// Kanji numerals, written with place values (二千二十六, 三百) or digit
    /// by digit (二〇二六).
    private static func parseKanji(in text: [Character], at start: Int) -> ParsedNumber? {
        var end = start
        while end < text.count, kanjiDigits[text[end]] != nil || kanjiMultipliers[text[end]] != nil || kanjiGroups[text[end]] != nil {
            end += 1
        }
        guard end > start, kanjiGroups[text[start]] == nil else { return nil }
        let characters = text[start..<end]

        // Two numerals in a row, the second one more, are a rough count:
        // 二三日 is two or three days, 四五人 four or five people.
        if characters.count == 2, let first = kanjiDigits[characters.first!], let second = kanjiDigits[characters.last!],
           first > 0, second == first + 1 {
            let spoken = Spoken(pieces: [roughKana[first]!] + Spoken(second).pieces, onesDigit: second)
            return ParsedNumber(start: start, end: end, text: String(characters), value: second, spoken: spoken, isDigits: false, rough: (first, second))
        }

        let value: Int
        if characters.contains("〇") || (characters.count > 1 && characters.allSatisfy { kanjiDigits[$0] != nil }) {
            guard characters.allSatisfy({ kanjiDigits[$0] != nil }) else { return nil }
            value = characters.reduce(0) { $0 * 10 + kanjiDigits[$1]! }
        } else {
            var total = 0, group = 0, digit = 0
            for character in characters {
                if let d = kanjiDigits[character] {
                    digit = d
                } else if let multiplier = kanjiMultipliers[character] {
                    group += max(digit, 1) * multiplier
                    digit = 0
                } else if let size = kanjiGroups[character] {
                    total += (group + digit) * size
                    group = 0
                    digit = 0
                }
            }
            value = total + group + digit
        }
        guard value > 0 else { return nil }
        return ParsedNumber(start: start, end: end, text: String(characters), value: value, spoken: Spoken(value), isDigits: false)
    }

    // MARK: Spoken numbers

    /// A number as spoken, in pieces, so a counter can change its last
    /// sound: いち + ほん → いっぽん.
    package struct Spoken {
        static let digitKana = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]

        var pieces: [String]
        /// The ones digit, if the number ends with one: 21 → 1, 20 → nil.
        var onesDigit: Int?

        var text: String { pieces.joined() }

        /// Pieces naming a thousand, hundred, or power of ten thousand.
        static let magnitudes: Set<String> = ["せん", "ぜん", "ひゃく", "びゃく", "ぴゃく", "まん", "おく", "ちょう"]

        init(pieces: [String], onesDigit: Int? = nil) {
            self.pieces = pieces
            self.onesDigit = onesDigit
        }

        init(_ value: Int) {
            guard value > 0 else {
                self.init(pieces: ["ぜろ"])
                return
            }
            var pieces: [String] = []
            var rest = value
            for (size, name) in [(1_000_000_000_000, "ちょう"), (100_000_000, "おく"), (10_000, "まん"), (1, "")] {
                let group = rest / size
                rest %= size
                guard group > 0 else { continue }
                pieces += Self.belowTenThousand(group)
                guard !name.isEmpty else { continue }
                // 一兆, 八兆, 十兆 double the consonant: いっちょう.
                if name == "ちょう", let last = pieces.last, let doubled = Self.doubled[last] {
                    pieces[pieces.count - 1] = doubled
                }
                pieces.append(name)
            }
            self.init(pieces: pieces, onesDigit: value % 10 == 0 ? nil : value % 10)
        }

        private static func belowTenThousand(_ value: Int) -> [String] {
            var pieces: [String] = []
            switch value / 1000 {
            case 0: break
            case 1: pieces.append("せん")
            case 3: pieces += ["さん", "ぜん"]
            case 8: pieces += ["はっ", "せん"]
            case let digit: pieces += [digitKana[digit], "せん"]
            }
            switch value / 100 % 10 {
            case 0: break
            case 1: pieces.append("ひゃく")
            case 3: pieces += ["さん", "びゃく"]
            case 6: pieces += ["ろっ", "ぴゃく"]
            case 8: pieces += ["はっ", "ぴゃく"]
            case let digit: pieces += [digitKana[digit], "ひゃく"]
            }
            switch value / 10 % 10 {
            case 0: break
            case 1: pieces.append("じゅう")
            case let digit: pieces += [digitKana[digit], "じゅう"]
            }
            if value % 10 > 0 { pieces.append(digitKana[value % 10]) }
            return pieces
        }

        /// Last pieces that double the next consonant: いっ, ろっ, じゅっ.
        static let doubled: [String: String] = [
            "いち": "いっ", "ろく": "ろっ", "はち": "はっ", "じゅう": "じゅっ",
            "ひゃく": "ひゃっ", "びゃく": "びゃっ", "ぴゃく": "ぴゃっ",
        ]
    }

    // MARK: Counters

    /// How a counter's first sound changes after the number.
    private enum Sound {
        /// No change: 枚, 台, 番.
        case none
        /// は-row counters (本, 匹, 杯, 分): ぽん after いっ, ろっ, はっ, じゅっ,
        /// ひゃっ; ぼん after さん, なん, せん, まん.
        case h
        /// か-row counters (回, 個, か月): っか after いち, ろく, はち, じゅう,
        /// ひゃく.
        case k
        /// さ- and た-row counters (冊, 歳, 足, 点): っさ after いち, はち,
        /// じゅう only.
        case st
    }

    private struct Counter {
        let spellings: [String]
        let kana: String
        var sound: Sound = .none
        /// The counter after さん and なん, if it changes: 三階 さんがい. For
        /// は-row counters, after よん too: 三分 さんぷん, 四分 よんぷん.
        var afterN: String? = nil
        /// The ones digit's reading before this counter: 四時 よじ.
        var digits: [Int: String] = [:]
        /// Readings of whole numbers that don't follow the pattern: 一人 ひとり.
        var whole: [Int: String] = [:]
        /// Whether only `whole` numbers have readings, as with native つ.
        var wholeOnly = false

        func read(_ number: Spoken, value: Int, afterMonth: Bool) -> String? {
            if kana == "にち" { return Self.day(number, value: value, afterMonth: afterMonth) }
            if let reading = whole[value] { return reading }
            guard !wholeOnly else { return nil }

            var pieces = number.pieces
            if let ones = number.onesDigit, let reading = digits[ones], pieces.last == Spoken.digitKana[ones] {
                pieces[pieces.count - 1] = reading
            }
            guard let last = pieces.last else { return nil }
            let head = pieces.dropLast().joined()

            switch sound {
            case .none:
                break
            case .h:
                if let doubled = Spoken.doubled[last] {
                    return head + doubled + Self.shift(kana, by: 2)
                }
                if let afterN, ["さん", "よん", "なん"].contains(last) {
                    return head + last + afterN
                }
                if ["さん", "なん", "せん", "まん"].contains(last) {
                    return head + last + Self.shift(kana, by: 1)
                }
            case .k:
                if let doubled = Spoken.doubled[last] {
                    return head + doubled + kana
                }
            case .st:
                if ["いち", "はち", "じゅう"].contains(last), let doubled = Spoken.doubled[last] {
                    return head + doubled + kana
                }
            }
            if let afterN, ["さん", "なん"].contains(last) {
                return head + last + afterN
            }
            return head + last + kana
        }

        /// Days of the month and counts of days.
        private static func day(_ number: Spoken, value: Int, afterMonth: Bool) -> String? {
            if value == 1 { return afterMonth ? "ついたち" : "いちにち" }
            let irregular = [2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか", 6: "むいか", 7: "なのか",
                             8: "ようか", 9: "ここのか", 10: "とおか", 20: "はつか"]
            if let reading = irregular[value] { return reading }
            var pieces = number.pieces
            let ones = number.onesDigit
            if let ones, pieces.last == Spoken.digitKana[ones] {
                switch ones {
                case 4: return (pieces.dropLast() + ["よっか"]).joined() // 十四日
                case 7: pieces[pieces.count - 1] = "しち"                  // 十七日
                case 9: pieces[pieces.count - 1] = "く"                    // 十九日
                default: break
                }
            }
            return pieces.joined() + "にち"
        }

        /// Moves a kana's first character along its row: は + 1 → ば,
        /// は + 2 → ぱ.
        private static func shift(_ kana: String, by amount: UInt32) -> String {
            guard let first = kana.unicodeScalars.first,
                  let shifted = Unicode.Scalar(first.value + amount)
            else { return kana }
            return String(Character(shifted)) + kana.dropFirst()
        }
    }

    /// Counters with rules, longest spellings matched first.
    private static let counters: [Counter] = [
        // Dates and times.
        Counter(spellings: ["年"], kana: "ねん", digits: [4: "よ"]),
        Counter(spellings: ["月"], kana: "がつ", digits: [4: "し", 7: "しち", 9: "く"]),
        Counter(spellings: ["日"], kana: "にち"),
        Counter(spellings: ["時間"], kana: "じかん", digits: [4: "よ", 7: "しち", 9: "く"]),
        Counter(spellings: ["時"], kana: "じ", digits: [4: "よ", 7: "しち", 9: "く"]),
        Counter(spellings: ["分"], kana: "ふん", sound: .h, afterN: "ぷん"),
        Counter(spellings: ["秒"], kana: "びょう"),
        Counter(spellings: ["週間"], kana: "しゅうかん", sound: .st),
        Counter(spellings: ["週"], kana: "しゅう", sound: .st),
        Counter(spellings: ["ヶ月", "か月", "カ月", "ヵ月", "箇月"], kana: "かげつ", sound: .k),

        // People and ages.
        Counter(spellings: ["人"], kana: "にん", digits: [4: "よ", 7: "しち"], whole: [1: "ひとり", 2: "ふたり"]),
        Counter(spellings: ["歳", "才"], kana: "さい", sound: .st, whole: [20: "はたち"]),

        // Things.
        Counter(spellings: ["本"], kana: "ほん", sound: .h),
        Counter(spellings: ["匹"], kana: "ひき", sound: .h),
        Counter(spellings: ["杯"], kana: "はい", sound: .h),
        Counter(spellings: ["泊"], kana: "はく", sound: .h, afterN: "ぱく"),
        Counter(spellings: ["回"], kana: "かい", sound: .k),
        Counter(spellings: ["階"], kana: "かい", sound: .k, afterN: "がい"),
        Counter(spellings: ["個"], kana: "こ", sound: .k),
        Counter(spellings: ["冊"], kana: "さつ", sound: .st),
        Counter(spellings: ["足"], kana: "そく", sound: .st, afterN: "ぞく"),
        Counter(spellings: ["点"], kana: "てん", sound: .st),
        Counter(spellings: ["枚"], kana: "まい"),
        Counter(spellings: ["台"], kana: "だい"),
        Counter(spellings: ["番"], kana: "ばん"),
        Counter(spellings: ["度"], kana: "ど"),
        Counter(spellings: ["倍"], kana: "ばい"),
        Counter(spellings: ["円"], kana: "えん", digits: [4: "よ"]),
        Counter(
            spellings: ["つ"], kana: "",
            whole: [1: "ひとつ", 2: "ふたつ", 3: "みっつ", 4: "よっつ", 5: "いつつ",
                    6: "むっつ", 7: "ななつ", 8: "やっつ", 9: "ここのつ"],
            wholeOnly: true
        ),
    ]
}
