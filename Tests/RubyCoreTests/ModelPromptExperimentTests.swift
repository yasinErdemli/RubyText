// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
import Foundation
import FoundationModels
@_spi(Experiments) @testable import RubyCore
import RubyMeCab
import Testing

/// Two sentences where the second has a word whose reading only the first
/// settles: 本当に辛かった is からかった after spicy ramen and つらかった after
/// a death in the family.
let neighborCases: [(text: String, word: String, reading: String)] = [
    ("昨日、激辛のラーメンを食べた。本当に辛かった。", "辛かっ", "からかっ"),
    ("祖母が亡くなった。本当に辛かった。", "辛かっ", "つらかっ"),
    ("夜中の公園に行った。人気がなかった。", "人気", "ひとけ"),
    ("新しい商品を発売した。でも人気がなかった。", "人気", "にんき"),
    ("スーパーで刺身を買った。生物だから今日中に食べる。", "生物", "なまもの"),
    ("理科の授業が好きだ。特に生物が面白い。", "生物", "せいぶつ"),
    ("受付に誰かいる。あの方に聞いてみよう。", "方", "かた"),
    ("道に迷ってしまった。あの方に行ってみよう。", "方", "ほう"),
    ("夜遅くまでゲームをしていた。もう止めよう。", "止めよ", "やめよ"),
    ("エンジンの音がうるさい。止めよう。", "止めよ", "とめよ"),
    ("彼は有名な書道家だ。その道の大家と呼ばれている。", "大家", "たいか"),
    ("家賃を払いに行った。大家は留守だった。", "大家", "おおや"),
    ("子供たちと折り紙をした。色紙を何枚も使った。", "色紙", "いろがみ"),
    ("卒業式で先生にお礼を言った。みんなで書いた色紙を渡した。", "色紙", "しきし"),
    ("熱が三十九度もある。寒気が止まらない。", "寒気", "さむけ"),
    ("明日は大雪になるらしい。強い寒気のせいだ。", "寒気", "かんき"),
    ("和菓子屋に寄った。最中を三つ買った。", "最中", "もなか"),
    ("会議で発表していた。その最中に電話が鳴った。", "最中", "さいちゅう"),
    ("サイを見に動物園へ行った。立派な角だった。", "角", "つの"),
    ("駅まではまっすぐ進む。次の角を右に曲がる。", "角", "かど"),
    ("朝のラッシュが終わった。電車は空いている。", "空い", "すい"),
    ("会議室の予約を確認した。午後なら空いている。", "空い", "あい"),
    ("戦後、日本は大きく発展した。今日の繁栄はその努力の結果だ。", "今日", "こんにち"),
    ("朝から雨が降っている。今日の予定は中止だ。", "今日", "きょう"),
]

/// The demo app's long text, and the reading of each word the model is
/// asked about, in order.
let diaryText = "今日は朝から寒気がして、仕事を休んだ。昼過ぎに大家さんが様子を見に来て、お見舞いに栗の最中を置いていった。夕方、少し良くなったので駅の方へ歩いた。角のパン屋はいつも人気で、今日も行列ができていた。帰りに通った公園は人気がなくて、少し怖かった。夜は友人と韓国料理の店に行った。料理はとても辛くて、水が手放せなかった。友人は「最近、仕事が辛い」と言い、タバコを止めたいと話した。帰りの電車は空いていたので座れた。本屋で生物の図鑑を買ったが、冷蔵庫の生物は明日までに食べないといけない。家に着くと、引っ越す先生への寄せ書きの色紙が届いていた。天気予報によると、北から強い寒気が流れ込むらしい。"
let diaryReadings = ["きょう", "さむけ", "おおや", "もなか", "ほう", "かど", "にんき", "きょう", "ひとけ", "からく", "つらい", "やめ", "すい", "せいぶつ", "なまもの", "しきし", "かんき"]

/// Compares prompts for the model layer: how many readings each gets right
/// and how long it takes. Asks a few hundred questions per prompt, so it
/// runs only when asked:
///
///     TEST_RUNNER_RUBY_PROMPT_EXPERIMENT=1 xcodebuild test … -only-testing:RubyCoreTests/ModelPromptExperimentTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUBY_PROMPT_EXPERIMENT"] != nil && SystemLanguageModel.default.isAvailable))
struct ModelPromptExperimentTests {
    private static let prompts: [(name: String, prompt: RubyModelOptions)] = [
        ("plain", RubyModelOptions(includesNeighbors: false, reasons: false)),
        ("reasons", RubyModelOptions(includesNeighbors: false, reasons: true)),
        ("standard", .standard),
        ("standard, together", RubyModelOptions(asksTogether: true)),
        // Private Cloud Compute needs an entitlement the test runner can't
        // have; without it, asking stops the process.
    ]

    /// A question and the reading it should get.
    private struct Case {
        let question: RubyReadingQuestion
        let reading: String
    }

    private static func cases(_ items: [(text: String, word: String, reading: String)]) -> [Case] {
        items.compactMap { item in
            let questions = RubyModelReadings.questions(in: item.text, analyzer: RubyMeCabAnalyzer.ipadic)
            guard let question = questions.first(where: { $0.word == item.word })
                ?? questions.first(where: { item.word.hasPrefix($0.word) || $0.word.hasPrefix(item.word) })
            else { return nil }
            return Case(question: question, reading: item.reading)
        }
    }

    private static var sets: [(name: String, cases: [Case])] {
        let diary = zip(RubyModelReadings.questions(in: diaryText, analyzer: RubyMeCabAnalyzer.ipadic), diaryReadings)
            .map { Case(question: $0, reading: $1) }
        return [
            ("neighbors", cases(neighborCases)),
            ("diary", diary),
            ("homographs", cases(homographCases.map { ($0.sentence, $0.word, $0.readings[0]) })),
            ("benchmark", cases(readingBenchmark.filter { $0.kind == .meaning }.map { ($0.sentence, $0.word, $0.readings[0]) })),
        ]
    }

    /// Whether `reading`, chosen for the question's word, is `expected`,
    /// which may spell out the rest of a longer word: 止め as やめ for
    /// 止めておく as やめておく.
    private static func isCorrect(_ reading: String, _ expected: String) -> Bool {
        reading == expected || (expected.hasPrefix(reading) && reading.count >= 2)
    }

    @Test func compare() async {
        let sets = Self.sets
        var lines = ["| Prompt | " + sets.map { "\($0.name) (\($0.cases.count))" }.joined(separator: " | ") + " | All | Median |"]
        lines.append("| --- |" + String(repeating: " --- |", count: sets.count + 2))
        // The dictionary alone, for reference.
        let dictionary = sets.map { set in set.cases.filter { Self.isCorrect($0.question.dictionaryReading, $0.reading) }.count }
        lines.append("| dictionary | " + dictionary.map(String.init).joined(separator: " | ") + " | \(dictionary.reduce(0, +)) | |")
        for (name, prompt) in Self.prompts {
            guard prompt.isAvailable else {
                lines.append("| \(name) | unavailable |")
                continue
            }
            let chooser = RubyLanguageModelChooser(options: prompt)
            var correct: [Int] = []
            var times: [Duration] = []
            var misses: [String] = []
            for set in sets {
                var count = 0
                // The diary's words are asked about together when the
                // options say to; every other text has one word.
                var together: [Int?]?
                if prompt.asksTogether && set.cases.count > 1 && set.name == "diary" {
                    let start = ContinuousClock.now
                    together = try? await chooser.choose(set.cases.map(\.question))
                    times.append(start.duration(to: .now))
                }
                for (position, item) in set.cases.enumerated() {
                    let index: Int?
                    if let together {
                        index = position < together.count ? together[position] : nil
                    } else {
                        let start = ContinuousClock.now
                        index = (try? await chooser.choose(item.question)) ?? nil
                        times.append(start.duration(to: .now))
                    }
                    let reading = index.flatMap { item.question.choices.indices.contains($0) ? item.question.choices[$0].reading : nil }
                        ?? item.question.dictionaryReading
                    if Self.isCorrect(reading, item.reading) {
                        count += 1
                    } else {
                        misses.append("\(set.name): \(item.question.word) → \(reading), should be \(item.reading) (\(item.question.sentence))")
                    }
                }
                correct.append(count)
            }
            times.sort()
            let median = Int(times[times.count / 2] / .milliseconds(1))
            lines.append("| \(name) | " + correct.map(String.init).joined(separator: " | ") + " | \(correct.reduce(0, +)) | \(median) ms |")
            print("PROMPT \(name) misses:\n" + misses.joined(separator: "\n"))
        }
        print("PROMPTS\n" + lines.joined(separator: "\n"))
    }
}
#endif
