import Foundation
import FoundationModels
import Synchronization

/// A word whose reading depends on its meaning, in a sentence, with the
/// readings it may have: what the language model is asked about.
@_spi(Experiments) public struct RubyReadingQuestion: Hashable, Sendable {
    /// The whole sentence the word is in.
    public let sentence: String
    /// The word as written.
    public let word: String
    /// The word with a few words around it, to point out which occurrence
    /// is meant: 人気のない早朝.
    public let context: String
    /// The readings the model chooses among.
    public let choices: [RubyReadingChoice]
    /// The reading the dictionary gave the word, one of `choices`.
    public let dictionaryReading: String
    /// `sentence` with the word in 【】, to show which occurrence is meant.
    package let markedSentence: String
    /// The sentences before and after, if any.
    package let previousSentence: String?
    package let nextSentence: String?
}

/// Chooses between the readings of a word whose reading depends on its
/// meaning, judging by the sentence around it.
///
/// Choosers are `Hashable` so answers can be cached per chooser.
package protocol RubyReadingChooser: Hashable, Sendable {
    /// The index in `question.choices` of the reading that fits, or `nil`
    /// to keep the dictionary's.
    func choose(_ question: RubyReadingQuestion) async throws -> Int?
    /// Whether to ask about a text's questions together, in as few
    /// requests as possible, rather than one at a time.
    var asksTogether: Bool { get }
    /// The index of the fitting reading for each of `questions`, in order.
    func choose(_ questions: [RubyReadingQuestion]) async throws -> [Int?]
}

extension RubyReadingChooser {
    package var asksTogether: Bool { false }

    package func choose(_ questions: [RubyReadingQuestion]) async throws -> [Int?] {
        var choices: [Int?] = []
        for question in questions {
            choices.append(try await choose(question))
        }
        return choices
    }
}

/// A language model as a tie-breaker for words whose reading depends on
/// their meaning (人気, 辛い, 方), which the dictionary reads the same way
/// in every sentence. `rubyModelReadings()` turns it on for `RubyText`.
///
/// Apple's on-device model answers by default. Any FoundationModels
/// `LanguageModel` can answer instead: Apple's larger model, as
/// `PrivateCloudComputeLanguageModel`, or a model from another provider
/// that conforms to `LanguageModel`. The model is asked through a
/// `LanguageModelSession`, with a schema that limits its answer to the
/// listed meanings, so it must support guided generation.
///
/// It runs after the rules, only on words on a built-in list that the
/// dictionary read, and only changes their readings, never where words
/// begin and end.
///
/// To measure the model, the questions it would ask and ways of asking
/// them are available with `@_spi(Experiments) import RubyCore`.
public nonisolated enum RubyModelReadings {
    /// Loads `model` and the instructions it's asked with ahead of the
    /// first question, which otherwise waits for them. Call it when a
    /// screen that will show readings by meaning appears, or earlier.
    public static func prewarm(_ model: any LanguageModel = SystemLanguageModel.default) {
        prewarm(options: RubyModelOptions(model: model))
    }

    /// Whether `model` can answer now. Apple's models know whether they're
    /// available here; other models are asked, and the dictionary's
    /// readings stay if they fail.
    package static func isAvailable(_ model: any LanguageModel) -> Bool {
        switch model {
        case let model as SystemLanguageModel: model.isAvailable
        case let model as PrivateCloudComputeLanguageModel: model.isAvailable
        default: true
        }
    }

    /// The questions `rubyModelReadings()` asks about `text`, read as it's
    /// written: one for each word on the list whose reading the dictionary
    /// chose, in text order.
    @_disfavoredOverload
    @_spi(Experiments) public static func questions(in text: some StringProtocol, analyzer: some RubyAnalyzer) -> [RubyReadingQuestion] {
        questions(in: RubyString(text: String(text)), analyzer: analyzer)
    }

    /// The questions `rubyModelReadings()` asks about `string`, outside the
    /// readings it gives and its unannotated text, in text order.
    @_spi(Experiments) public static func questions(in string: RubyString, analyzer: some RubyAnalyzer) -> [RubyReadingQuestion] {
        let (text, manual, unannotated) = RubyContent.parse(string)
        let segments = RubyContent.segments(in: text, analyzer: analyzer)
        return questions(in: segments, excluding: manual.map(\.range) + unannotated).map(\.question)
    }

    /// Asks the model about `question` now, and returns the reading it
    /// chose, or `nil` where the model isn't available.
    ///
    /// Unlike `answer(to:options:)`, which asks each question once, this
    /// always asks, so it can be timed. The answer is kept for `RubyText`
    /// views and `answer(to:options:)`.
    @_spi(Experiments) public static func ask(_ question: RubyReadingQuestion, options: RubyModelOptions = .standard) async throws -> RubyReadingChoice? {
        try await ask([question], options: options)[0]
    }

    /// Asks the model about `questions` now, as `options` say: together in
    /// as few requests as possible, or one at a time. Returns the reading
    /// it chose for each, in order. The answers are kept, as with
    /// `ask(_:options:)`.
    @_spi(Experiments) public static func ask(_ questions: [RubyReadingQuestion], options: RubyModelOptions = .standard) async throws -> [RubyReadingChoice?] {
        let chooser = RubyLanguageModelChooser(options: options)
        var indices: [Int?] = []
        for chunk in chunks(of: questions, chooser: chooser) {
            indices += try await chooser.choose(chunk)
        }
        return zip(questions, indices).map { question, index in
            guard let index, question.choices.indices.contains(index) else { return nil }
            let key = AnswerKey(question: question, chooser: AnyHashable(chooser))
            answers.withLock { $0[key] = Task { index } }
            return question.choices[index]
        }
    }

    /// The model's answer to `question`, as `RubyText` views get it: asked
    /// once and kept, and asked once even when several views ask at the
    /// same time. `nil` where the model isn't available or can't answer.
    @_spi(Experiments) public static func answer(to question: RubyReadingQuestion, options: RubyModelOptions = .standard) async -> RubyReadingChoice? {
        await answers(to: [question], options: options)[0]
    }

    /// The model's answers to `questions`, as `RubyText` views get them,
    /// asked together or one at a time as `options` say.
    @_spi(Experiments) public static func answers(to questions: [RubyReadingQuestion], options: RubyModelOptions = .standard) async -> [RubyReadingChoice?] {
        let chooser = RubyLanguageModelChooser(options: options)
        let tasks = chooser.asksTogether ? startAnswering(questions, chooser: chooser) : nil
        var choices: [RubyReadingChoice?] = []
        for (position, question) in questions.enumerated() {
            let index = if let tasks {
                await finish(tasks[position], for: question, chooser: chooser)
            } else {
                await answer(question, chooser: chooser)
            }
            choices.append(index.flatMap { question.choices.indices.contains($0) ? question.choices[$0] : nil })
        }
        return choices
    }

    /// Loads the model and the instructions `options` ask with ahead of
    /// the first question.
    @_spi(Experiments) public static func prewarm(options: RubyModelOptions) {
        RubyLanguageModelChooser.prewarm(options: options)
    }

    /// The questions to ask about `segments`, which cover a whole text,
    /// with the index of the segment each one is about. Segments touching
    /// `excluded` UTF-16 ranges, such as manual readings, are skipped.
    package static func questions(in segments: [RubySegment], excluding excluded: [Range<Int>] = []) -> [(index: Int, question: RubyReadingQuestion)] {
        var result: [(index: Int, question: RubyReadingQuestion)] = []
        var offsets: [Int] = []
        var offset = 0
        for segment in segments {
            offsets.append(offset)
            offset += segment.base.utf16.count
        }
        let sentences = sentences(in: segments)
        let texts = sentences.map { sentence in
            segments[sentence].map(\.base).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (number, sentence) in sentences.enumerated() {
            let text = segments[sentence].map(\.base).joined()
            for index in sentence where segments[index].source == .dictionary {
                let segment = segments[index]
                let range = offsets[index]..<(offsets[index] + segment.base.utf16.count)
                guard !excluded.contains(where: { $0.overlaps(range) }),
                      let choices = RubyHomographs.choices(for: segment)
                else { continue }
                let marked = segments[sentence].indices.map { $0 == index ? "【\(segments[$0].base)】" : segments[$0].base }
                result.append((index, RubyReadingQuestion(
                    sentence: text,
                    word: segment.base,
                    context: context(of: index, in: segments, within: sentence),
                    choices: choices,
                    dictionaryReading: segment.reading ?? "",
                    markedSentence: marked.joined().trimmingCharacters(in: .whitespacesAndNewlines),
                    previousSentence: number > 0 && !texts[number - 1].isEmpty ? texts[number - 1] : nil,
                    nextSentence: number + 1 < texts.count && !texts[number + 1].isEmpty ? texts[number + 1] : nil
                )))
            }
        }
        return result
    }

    /// Forgets every reading the model has chosen, so `RubyText` views ask
    /// again the next time they load: to watch or measure the model, or
    /// after a system update changes it.
    @_spi(Experiments) public static func forgetAnswers() {
        answers.withLock { $0.removeAll() }
        RubyContent.forgetModelReadings()
    }

    /// `segments` with the readings `chooser` picks for words on the
    /// homograph list, each marked as from the model. Words it can't answer
    /// about keep the dictionary's reading.
    ///
    /// - Parameter onChange: Called with the segments so far each time an
    ///   answer changes a reading.
    package static func apply(
        to segments: [RubySegment],
        excluding excluded: [Range<Int>] = [],
        chooser: some RubyReadingChooser,
        onChange: (([RubySegment]) async -> Void)? = nil
    ) async -> [RubySegment] {
        var result = segments
        let asked = questions(in: segments, excluding: excluded)
        let tasks = chooser.asksTogether ? startAnswering(asked.map(\.question), chooser: chooser) : nil
        for (position, (index, question)) in asked.enumerated() {
            let answer = if let tasks {
                await finish(tasks[position], for: question, chooser: chooser)
            } else {
                await answer(question, chooser: chooser)
            }
            guard let choice = answer,
                  question.choices.indices.contains(choice),
                  question.choices[choice].reading != result[index].reading
            else { continue }
            result[index].reading = question.choices[choice].reading
            // The pronunciation was for the dictionary's reading.
            result[index].pronunciation = nil
            result[index].source = .model
            await onChange?(result)
        }
        return result
    }

    /// Answers given or being given, so each question is asked once per
    /// chooser, however many views ask about it at the same time.
    private static let answers = Mutex<[AnswerKey: Task<Int?, Never>]>([:])

    private struct AnswerKey: Hashable {
        let question: RubyReadingQuestion
        let chooser: AnyHashable
    }

    /// The most questions asked about in one request, so a long text's
    /// prompt fits the on-device model's context.
    private static let questionsPerRequest = 20

    /// `questions` in groups of as many as `chooser` asks about at once.
    private static func chunks(of questions: [RubyReadingQuestion], chooser: some RubyReadingChooser) -> [[RubyReadingQuestion]] {
        let size = chooser.asksTogether ? questionsPerRequest : 1
        return stride(from: 0, to: questions.count, by: size).map { Array(questions[$0..<min($0 + size, questions.count)]) }
    }

    private static func answer(_ question: RubyReadingQuestion, chooser: some RubyReadingChooser) async -> Int? {
        let key = AnswerKey(question: question, chooser: AnyHashable(chooser))
        let task = answers.withLock { answers in
            if let task = answers[key] { return task }
            if answers.count >= 1000 { answers.removeAll() }
            let task = Task { try? await chooser.choose(question) }
            answers[key] = task
            return task
        }
        return await finish(task, for: question, chooser: chooser)
    }

    /// Tasks answering each of `questions`: the ones already asked about,
    /// and requests together for the rest.
    private static func startAnswering(_ questions: [RubyReadingQuestion], chooser: some RubyReadingChooser) -> [Task<Int?, Never>] {
        let keys = questions.map { AnswerKey(question: $0, chooser: AnyHashable(chooser)) }
        return answers.withLock { answers in
            if answers.count >= 1000 { answers.removeAll() }
            let unasked = keys.indices.filter { answers[keys[$0]] == nil }
            for chunk in stride(from: 0, to: unasked.count, by: questionsPerRequest).map({ unasked[$0..<min($0 + questionsPerRequest, unasked.count)] }) {
                let asked = chunk.map { questions[$0] }
                let request = Task { (try? await chooser.choose(asked)) ?? [] }
                for (position, index) in chunk.enumerated() {
                    answers[keys[index]] = Task {
                        let choices = await request.value
                        return position < choices.count ? choices[position] : nil
                    }
                }
            }
            return keys.map { answers[$0]! }
        }
    }

    /// The answer `task` gives. No answer, such as when the model refuses a
    /// sentence, keeps the dictionary's reading, and isn't kept, so a later
    /// try can succeed.
    private static func finish(_ task: Task<Int?, Never>, for question: RubyReadingQuestion, chooser: some RubyReadingChooser) async -> Int? {
        let choice = await task.value
        if choice == nil {
            let key = AnswerKey(question: question, chooser: AnyHashable(chooser))
            answers.withLock { answers in
                if answers[key] == task { answers[key] = nil }
            }
        }
        return choice
    }

    /// Ranges of segment indices, one per sentence, each ending with the
    /// segment that ends the sentence (。, ！, ？ or a line break).
    private static func sentences(in segments: [RubySegment]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        for (index, segment) in segments.enumerated() where segment.base.contains(where: sentenceEnds.contains) {
            result.append(start..<(index + 1))
            start = index + 1
        }
        if start < segments.count { result.append(start..<segments.count) }
        return result
    }

    private static let sentenceEnds: Set<Character> = ["。", "！", "？", "!", "?", "\n"]

    /// The segment at `index` with up to two words before and after it in
    /// the same clause.
    private static func context(of index: Int, in segments: [RubySegment], within sentence: Range<Int>) -> String {
        func isWord(_ segment: RubySegment) -> Bool {
            segment.base.contains { $0.isLetter || $0.isNumber }
        }
        var lower = index
        while lower > sentence.lowerBound, index - lower < 2, isWord(segments[lower - 1]) { lower -= 1 }
        var upper = index + 1
        while upper < sentence.upperBound, upper - index <= 2, isWord(segments[upper]) { upper += 1 }
        return segments[lower..<upper].map(\.base).joined()
    }
}

/// How readings by meaning are asked for: which model answers, how, and
/// what it's told. Each option can be turned on separately, to compare how
/// well a model reads with it.
@_spi(Experiments) public struct RubyModelOptions: Hashable, Sendable {
    /// The model that answers: Apple's on-device model unless another is
    /// given.
    public var model: any LanguageModel {
        get { identity.model }
        set { identity = RubyModelIdentity(newValue) }
    }

    private var identity: RubyModelIdentity
    /// Ask about every word in a text together, in one request, rather
    /// than one word at a time. Fewer requests matter most with Private
    /// Cloud Compute, where each goes over the network.
    public var asksTogether = false
    /// Show each meaning with its reading: からい: spicy, hot or salty.
    public var showsReadings = false
    /// Mark the word in the sentence, 夜の公園は【人気】がない, rather than
    /// quoting the words around it.
    public var marksWord = false
    /// Add the sentences before and after the word's. On by default: with
    /// a reason, it settles words whose own sentence leaves them open,
    /// such as 本当に辛かった after 激辛のラーメンを食べた.
    public var includesNeighbors = true
    /// Give the instructions in Japanese.
    public var isJapanese = false
    /// Have the model say in a few words what the word means before it
    /// chooses. On by default: it picks rarer readings, such as 色紙 as
    /// しきし, much more often, though each answer takes about twice as
    /// long.
    public var reasons = true

    public init(
        model: any LanguageModel = SystemLanguageModel.default,
        asksTogether: Bool = false,
        showsReadings: Bool = false,
        marksWord: Bool = false,
        includesNeighbors: Bool = true,
        isJapanese: Bool = false,
        reasons: Bool = true
    ) {
        self.identity = RubyModelIdentity(model)
        self.asksTogether = asksTogether
        self.showsReadings = showsReadings
        self.marksWord = marksWord
        self.includesNeighbors = includesNeighbors
        self.isJapanese = isJapanese
        self.reasons = reasons
    }

    /// How `RubyText` asks by default: the on-device model, one word at a
    /// time, with the sentences around it and a reason before it chooses.
    /// On the benchmark's homographs, this reads 71 of 79 right, against
    /// 60 without the reason and the sentences around it.
    public static let standard = RubyModelOptions()

    /// Whether the model can answer: Apple's on-device model where Apple
    /// Intelligence is on and the model downloaded, and Private Cloud
    /// Compute where it's reachable, though only apps with its entitlement
    /// can ask it. Other models are assumed to be.
    public var isAvailable: Bool {
        RubyModelReadings.isAvailable(model)
    }

    /// The instructions the model's session starts with.
    public var instructions: String {
        isJapanese
            ? "あなたは日本語を読みます。挙げた語は文の中にあり、読み方が複数あって、読み方ごとに意味が違います。文に合う意味を選んでください。"
            : """
            You read Japanese. Each listed word appears in the sentence and can be read \
            in more than one way, each reading with a different meaning. For each word, \
            choose the meaning that fits the sentence.
            """
    }

    /// The options the model chooses among for `question`, in order.
    func options(for question: RubyReadingQuestion) -> [String] {
        question.choices.map { showsReadings ? "\($0.reading): \($0.meaning)" : $0.meaning }
    }

    /// Where the word is, as the prompt and schema point to it.
    func word(in question: RubyReadingQuestion, together: Bool) -> String {
        switch (marksWord, together) {
        case (true, false): "【\(question.word)】"
        case (true, true): "【\(question.word)】 in 「\(question.markedSentence)」"
        case (false, _): "\(question.word) in 「\(question.context)」"
        }
    }

    /// The prompt asking about `questions` together: one sentence and its
    /// word, or the sentences of a text and each of its words.
    public func prompt(for questions: [RubyReadingQuestion]) -> String {
        guard let first = questions.first else { return "" }
        var lines: [String] = []
        if questions.count == 1 {
            if includesNeighbors, let previous = first.previousSentence {
                lines.append("Before it: \(previous)")
            }
            lines.append("Sentence: \(marksWord ? first.markedSentence : first.sentence)")
            if includesNeighbors, let next = first.nextSentence {
                lines.append("After it: \(next)")
            }
        } else {
            // The sentences the words are in, and those around them if
            // asked for, each once and in order.
            var sentences: [String] = []
            for question in questions {
                let around = includesNeighbors ? [question.previousSentence, question.sentence, question.nextSentence] : [question.sentence]
                for sentence in around.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                where !sentence.isEmpty && !sentences.contains(sentence) {
                    sentences.append(sentence)
                }
            }
            lines.append("Text: \(sentences.joined())")
        }
        lines.append("")
        lines.append("Words:")
        for (number, question) in questions.enumerated() {
            lines.append("\(number + 1). \(word(in: question, together: questions.count > 1)): \(options(for: question).joined(separator: " or "))")
        }
        return lines.joined(separator: "\n")
    }
}

/// A language model, the same as another of its type with the same
/// configuration, so answers can be kept for each model.
private struct RubyModelIdentity: Hashable, Sendable {
    let model: any LanguageModel

    init(_ model: any LanguageModel) {
        self.model = model
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model.isSameModel(as: rhs.model)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type(of: model)))
        hasher.combine(model.executorConfiguration)
    }
}

extension LanguageModel {
    /// Whether `other` is this model: of the same type, configured the
    /// same way.
    fileprivate func isSameModel(as other: any LanguageModel) -> Bool {
        guard let other = other as? Self else { return false }
        return executorConfiguration == other.executorConfiguration
    }
}

/// Asks a language model which meaning words have in their sentences.
///
/// Each request has a fresh session, constrained to the listed meanings,
/// with greedy sampling so the same question always gets the same answer.
/// By default it asks about one word at a time, which is slower than
/// asking about a whole text at once but more accurate with the on-device
/// model: with several words in one request, it mixes up their meanings.
package struct RubyLanguageModelChooser: RubyReadingChooser {
    package let options: RubyModelOptions

    package init(options: RubyModelOptions = .standard) {
        self.options = options
    }

    package var asksTogether: Bool { options.asksTogether }

    private static func session(_ options: RubyModelOptions) -> LanguageModelSession {
        LanguageModelSession(model: options.model, instructions: options.instructions)
    }

    /// The session `prewarm()` loaded the model with, kept so loading
    /// isn't cancelled.
    private static let warmSession = Mutex<LanguageModelSession?>(nil)

    static func prewarm(options: RubyModelOptions) {
        guard options.isAvailable else { return }
        let session = session(options)
        session.prewarm()
        warmSession.withLock { $0 = session }
    }

    package func choose(_ question: RubyReadingQuestion) async throws -> Int? {
        try await choose([question]).first ?? nil
    }

    package func choose(_ questions: [RubyReadingQuestion]) async throws -> [Int?] {
        guard options.isAvailable, !questions.isEmpty else { return questions.map { _ in nil } }
        let together = questions.count > 1
        var properties: [DynamicGenerationSchema.Property] = []
        for (number, question) in questions.enumerated() {
            // One question keeps the names it has always had.
            let suffix = together ? "\(number + 1)" : ""
            let word = options.word(in: question, together: together)
            if options.reasons {
                properties.append(DynamicGenerationSchema.Property(
                    name: "reason" + suffix,
                    description: "In a few words, what \(word) means in this sentence",
                    schema: DynamicGenerationSchema(type: String.self)
                ))
            }
            properties.append(DynamicGenerationSchema.Property(
                name: "meaning" + suffix,
                description: "The meaning of \(word)",
                schema: DynamicGenerationSchema(name: "Meaning" + suffix, anyOf: options.options(for: question))
            ))
        }
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(name: "Readings", properties: properties),
            dependencies: []
        )
        let response = try await Self.session(options).respond(
            to: options.prompt(for: questions),
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return try questions.enumerated().map { number, question in
            let meaning = try response.content.value(String.self, forProperty: "meaning" + (together ? "\(number + 1)" : ""))
            // Some models change the capitalization of the meaning they
            // choose.
            return options.options(for: question).firstIndex { $0.caseInsensitiveCompare(meaning) == .orderedSame }
        }
    }
}
