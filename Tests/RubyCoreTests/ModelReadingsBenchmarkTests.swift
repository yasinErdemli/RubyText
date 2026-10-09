import Foundation
@_spi(Experiments) @testable import RubyCore
import Testing

private func h(_ sentence: String, _ word: String, _ reading: String) -> BenchmarkCase {
    BenchmarkCase(sentence: sentence, word: word, readings: [reading], kind: .meaning, mecab: nil)
}

/// More sentences for the words on the homograph list, each reading of
/// each word in turn, to check the model layer beyond the benchmark's
/// sentences. The meanings it chooses between were written against the
/// first half; the second half was only scored once they were done.
let homographCases = [
    h("この歌手は若者に人気だ。", "人気", "にんき"),
    h("夜の公園は人気がなくて怖い。", "人気", "ひとけ"),
    h("このカレーは辛すぎる。", "辛", "から"),
    h("毎朝早く起きるのは辛い。", "辛い", "つらい"),
    h("韓国料理は辛い。", "辛い", "からい"),
    h("生物は早めに食べてください。", "生物", "なまもの"),
    h("海には多くの生物がいる。", "生物", "せいぶつ"),
    h("駅はあちらの方です。", "方", "ほう"),
    h("受付の方に聞いてください。", "方", "かた"),
    h("タバコを止めることにした。", "止める", "やめる"),
    h("警察官が車を止めた。", "止め", "とめ"),
    h("大家さんに家賃を払った。", "大家", "おおや"),
    h("彼は日本画の大家だ。", "大家", "たいか"),
    h("今日は雨が降っている。", "今日", "きょう"),
    h("今日の日本社会では少子化が問題になっている。", "今日", "こんにち"),
    h("子供たちが色紙で飛行機を作った。", "色紙", "いろがみ"),
    h("卒業する先生に寄せ書きの色紙を贈った。", "色紙", "しきし"),
    h("熱が出て寒気がする。", "寒気", "さむけ"),
    h("北から強い寒気が流れ込む。", "寒気", "かんき"),
    h("試験の最中に眠くなった。", "最中", "さいちゅう"),
    h("お土産に栗の最中を買った。", "最中", "もなか"),
    h("本を開いてください。", "開い", "ひらい"),
    h("袋に穴が開いている。", "開い", "あい"),
    h("朝の電車は空いている。", "空い", "すい"),
    h("手が空いたら手伝って。", "空い", "あい"),
    h("机の角に足をぶつけた。", "角", "かど"),
    h("鹿の角が落ちていた。", "角", "つの"),
    h("二本の線が作る角を測る。", "角", "かく"),

    // Scored once, after the meanings were written.
    h("人気のない道を一人で歩いた。", "人気", "ひとけ"),
    h("人気の店には行列ができる。", "人気", "にんき"),
    h("辛いラーメンが好きだ。", "辛い", "からい"),
    h("失恋して辛い日々が続いた。", "辛い", "つらい"),
    h("夏は生物が傷みやすい。", "生物", "なまもの"),
    h("地球上の生物は水が必要だ。", "生物", "せいぶつ"),
    h("あの背の高い方はどなたですか。", "方", "かた"),
    h("右の方へ進んでください。", "方", "ほう"),
    h("夜更かしを止めたい。", "止め", "やめ"),
    h("信号で車を止めた。", "止め", "とめ"),
    h("アパートの大家に連絡した。", "大家", "おおや"),
    h("茶道の大家に教わった。", "大家", "たいか"),
    h("今日のテストは難しかった。", "今日", "きょう"),
    h("今日では誰もがスマートフォンを持っている。", "今日", "こんにち"),
    h("色紙を切って星を作った。", "色紙", "いろがみ"),
    h("有名人の色紙が飾ってある。", "色紙", "しきし"),
    h("風邪をひいて寒気が止まらない。", "寒気", "さむけ"),
    h("寒気の影響で大雪になった。", "寒気", "かんき"),
    h("授業の最中に地震があった。", "最中", "さいちゅう"),
    h("最中とお茶を出した。", "最中", "もなか"),
    h("来月、展覧会を開く。", "開く", "ひらく"),
    h("壁に穴が開いた。", "開い", "あい"),
    h("道が空いていたので早く着いた。", "空い", "すい"),
    h("この席は空いていますか。", "空い", "あい"),
    h("犬が塀の角を曲がった。", "角", "かど"),
    h("サイの角は高く売られる。", "角", "つの"),
    h("この角は九十度だ。", "角", "かく"),
]

/// The benchmark with Foundation Models as a tie-breaker. Runs only where
/// Apple Intelligence is available, such as a Mac with it turned on.
@Suite(.enabled(if: RubyModelReadings.isAvailable, "Apple Intelligence isn't available"))
struct ModelReadingsBenchmarkTests {
    /// Fails for any reading the dictionary got right and the model
    /// changed, and prints the scores with and without the model.
    @Test func score() async {
        #if canImport(FoundationModels)
        var lines: [String] = []
        for (name, cases) in [("Benchmark", readingBenchmark), ("Homographs", homographCases)] {
            var dictionaryCorrect = 0
            var modelCorrect = 0
            var details: [String] = []
            for benchmark in cases {
                let content = await RubyContent.content(for: benchmark.sentence, chooser: RubyFoundationModelsChooser())
                let dictionary = benchmark.actual
                let model = reading(of: benchmark.word, in: content)
                let wasCorrect = dictionary.map(benchmark.readings.contains) ?? false
                let isCorrect = model.map(benchmark.readings.contains) ?? false
                if wasCorrect { dictionaryCorrect += 1 }
                if isCorrect { modelCorrect += 1 }
                let label = "\(benchmark.word) in \(benchmark.sentence)"
                if wasCorrect && !isCorrect {
                    Issue.record("The model changed \(label) to \(model ?? "(not found)") from \(dictionary ?? "")")
                } else if !wasCorrect && isCorrect {
                    details.append("- fixed: \(label) → \(model ?? "")")
                } else if !isCorrect && benchmark.kind == .meaning {
                    details.append("- still \(model ?? "(not found)"): \(label), should be \(benchmark.readings[0])")
                }
            }
            lines.append("\(name): dictionary \(dictionaryCorrect) of \(cases.count), with the model \(modelCorrect)")
            lines += details
        }
        print(lines.joined(separator: "\n"))
        #endif
    }
}
