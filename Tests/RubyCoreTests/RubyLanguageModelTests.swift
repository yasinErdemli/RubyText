import Foundation
import FoundationModels
@_spi(Experiments) @testable import RubyCore
import Synchronization
import Testing

/// A language model from somewhere other than Apple, standing in for one
/// from another provider: it answers with the listed meaning that mentions
/// `keyword`, the way any model answering with guided generation would.
private struct KeywordModel: LanguageModel {
    typealias Executor = KeywordExecutor

    var keyword: String
    /// Whether to change the meaning's capitalization, as some models do.
    var capitalizes = false
    /// Whether every request fails, as one over a lost connection would.
    var fails = false

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.guidedGeneration]) }
    var executorConfiguration: KeywordExecutor.Configuration {
        KeywordExecutor.Configuration(keyword: keyword, capitalizes: capitalizes, fails: fails)
    }
}

private struct KeywordExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {
        var keyword: String
        var capitalizes: Bool
        var fails: Bool
    }

    typealias Model = KeywordModel

    /// The instructions and prompts each model was asked with, by keyword.
    static let requests = Mutex<[String: [String]]>([:])

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: KeywordModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let text = request.transcript.map { entry -> String in
            let segments: [Transcript.Segment] = switch entry {
            case .instructions(let instructions): instructions.segments
            case .prompt(let prompt): prompt.segments
            default: []
            }
            return segments.map { (segment: Transcript.Segment) -> String in
                guard case .text(let text) = segment else { return "" }
                return text.content
            }.joined()
        }
        Self.requests.withLock { $0[configuration.keyword, default: []] += text }
        if configuration.fails { throw URLError(.notConnectedToInternet) }

        // Fill in the schema: the meaning that mentions the keyword for
        // each choice, and a few words for each reason.
        let schema = try #require(request.schema)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(schema)) as? [String: Any]
        let properties = try #require(json?["properties"] as? [String: [String: Any]])
        var answer: [String: String] = [:]
        for (name, property) in properties {
            if let meanings = property["enum"] as? [String] {
                let meaning = meanings.first { $0.contains(configuration.keyword) } ?? meanings[0]
                answer[name] = configuration.capitalizes ? meaning.capitalized : meaning
            } else {
                answer[name] = "a guess"
            }
        }
        let reply = String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
        await channel.send(.response(action: .appendText(reply, tokenCount: 1)))
    }
}

/// Readings by meaning from any FoundationModels `LanguageModel`, not only
/// Apple's.
struct RubyLanguageModelTests {
    private func questions(_ text: String) -> [RubyReadingQuestion] {
        RubyModelReadings.questions(in: text, analyzer: RubyMeCabAnalyzer.ipadic)
    }

    @Test func anyLanguageModelChoosesReadings() async throws {
        let options = RubyModelOptions(model: KeywordModel(keyword: "presence"))
        let choices = await RubyModelReadings.answers(to: questions("夜の公園は人気がなくて怖い。"), options: options)
        #expect(choices.map(\.?.reading) == ["ひとけ"])
    }

    @Test func modelsAreAskedAboutTheSentence() async throws {
        let options = RubyModelOptions(model: KeywordModel(keyword: "popularity"))
        _ = await RubyModelReadings.answers(to: questions("この歌手は若者に人気だ。"), options: options)
        let asked = KeywordExecutor.requests.withLock { $0["popularity"] ?? [] }.joined(separator: "\n")
        #expect(asked.contains(options.instructions))
        #expect(asked.contains("この歌手は若者に人気だ。"))
        #expect(asked.contains("人気"))
    }

    @Test func meaningsMatchWhateverTheirCapitalization() async {
        let options = RubyModelOptions(model: KeywordModel(keyword: "painful", capitalizes: true))
        let choices = await RubyModelReadings.answers(to: questions("毎朝早く起きるのは辛い。"), options: options)
        #expect(choices.map(\.?.reading) == ["つらい"])
    }

    @Test func failedRequestsKeepTheDictionarysReadings() async {
        let model = KeywordModel(keyword: "taste", fails: true)
        let choices = await RubyModelReadings.answers(to: questions("このカレーは辛すぎる。"), options: RubyModelOptions(model: model))
        #expect(choices.allSatisfy { $0 == nil })

        let content = await RubyContent.content(
            for: "夜の公園は人気がなくて怖い。",
            analyzer: RubyMeCabAnalyzer.ipadic,
            chooser: RubyLanguageModelChooser(options: RubyModelOptions(model: model))
        )
        #expect(!content.words.contains { $0.source == .model })
    }

    @Test func modelsReadingsAreMarkedAsTheModels() async {
        let content = await RubyContent.content(
            for: "夜の公園は人気がなくて怖い。",
            analyzer: RubyMeCabAnalyzer.ipadic,
            chooser: RubyLanguageModelChooser(options: RubyModelOptions(model: KeywordModel(keyword: "deserted")))
        )
        let word = content.words.first { $0.source == .model }
        #expect(word?.furigana.map(\.text) == ["ひとけ"])
    }

    /// Answers are kept for each model, so two models don't share them, and
    /// options naming the same model are the same options.
    @Test func answersAreKeptForEachModel() async {
        let question = questions("辛いラーメンが好きだ。")
        let spicy = await RubyModelReadings.answers(to: question, options: RubyModelOptions(model: KeywordModel(keyword: "spicy")))
        let painful = await RubyModelReadings.answers(to: question, options: RubyModelOptions(model: KeywordModel(keyword: "hard to bear")))
        #expect(spicy.map(\.?.reading) == ["からい"])
        #expect(painful.map(\.?.reading) == ["つらい"])

        #expect(RubyModelOptions(model: KeywordModel(keyword: "a")) == RubyModelOptions(model: KeywordModel(keyword: "a")))
        #expect(RubyModelOptions(model: KeywordModel(keyword: "a")) != RubyModelOptions(model: KeywordModel(keyword: "b")))
        #expect(RubyModelOptions(model: KeywordModel(keyword: "a")) != .standard)
    }

    /// Apple's models compare equal however they're created, so views
    /// don't ask again each time they're updated.
    @Test func applesModelsAreTheSameEachTime() {
        #expect(RubyModelOptions() == .standard)
        #expect(RubyModelOptions(model: SystemLanguageModel.default) == .standard)
        #expect(RubyModelOptions(model: PrivateCloudComputeLanguageModel()) == RubyModelOptions(model: PrivateCloudComputeLanguageModel()))
        #expect(RubyModelOptions(model: PrivateCloudComputeLanguageModel()) != .standard)
    }
}
