import Foundation
import Synchronization
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A word whose reading depends on its meaning, in a sentence, with the
/// readings it may have: what Apple's on-device model is asked about.
public struct RubyReadingQuestion: Hashable, Sendable {
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
}

/// Chooses between the readings of a word whose reading depends on its
/// meaning, judging by the sentence around it.
///
/// Choosers are `Hashable` so answers can be cached per chooser.
package protocol RubyReadingChooser: Hashable, Sendable {
    /// The index in `question.choices` of the reading that fits, or `nil`
    /// to keep the dictionary's.
    func choose(_ question: RubyReadingQuestion) async throws -> Int?
}

/// Apple's on-device model as a tie-breaker for words whose reading depends
/// on their meaning (人気, 辛い, 方), which the dictionary reads the same way
/// in every sentence. `rubyModelReadings()` turns it on for `RubyText`.
///
/// It runs after the rules, only on words on a built-in list that the
/// dictionary read, and only changes their readings, never where words
/// begin and end. The questions it would ask, and asking them one by one,
/// are public, to see what it does and how long it takes:
///
///     for question in RubyModelReadings.questions(in: text, analyzer: analyzer) {
///         let start = ContinuousClock.now
///         let choice = try await RubyModelReadings.ask(question)
///         print(question.word, choice?.reading ?? "-", ContinuousClock.now - start)
///     }
public nonisolated enum RubyModelReadings {
    /// Whether Apple's on-device model is available on this device, with
    /// Apple Intelligence turned on and the model downloaded.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        RubyFoundationModelsChooser.isAvailable
        #else
        false
        #endif
    }

    /// The questions `rubyModelReadings()` asks about `markup`: one for each
    /// word on the list whose reading the dictionary chose, outside
    /// readings you supply in `{base|reading}` markup, in text order.
    public static func questions(in markup: String, analyzer: some RubyAnalyzer) -> [RubyReadingQuestion] {
        let (string, manual) = RubyContent.parse(markup)
        let segments = RubyContent.segments(in: string, analyzer: analyzer)
        return questions(in: segments, excluding: manual.map(\.range)).map(\.question)
    }

    /// Asks the model `question` now, and returns the reading it chose, or
    /// `nil` where the model isn't available.
    ///
    /// Unlike `answer(to:)`, which asks each question once, this always
    /// asks, so it can be timed. The answer is kept for `RubyText` views
    /// and `answer(to:)`.
    public static func ask(_ question: RubyReadingQuestion) async throws -> RubyReadingChoice? {
        #if canImport(FoundationModels)
        let chooser = RubyFoundationModelsChooser()
        guard let index = try await chooser.choose(question),
              question.choices.indices.contains(index)
        else { return nil }
        answers.withLock { $0[AnswerKey(question: question, chooser: AnyHashable(chooser))] = Task { index } }
        return question.choices[index]
        #else
        return nil
        #endif
    }

    /// The model's answer to `question`, as `RubyText` views get it: asked
    /// once and kept, and asked once even when several views ask at the
    /// same time. `nil` where the model isn't available or can't answer.
    public static func answer(to question: RubyReadingQuestion) async -> RubyReadingChoice? {
        #if canImport(FoundationModels)
        guard let index = await answer(question, chooser: RubyFoundationModelsChooser()),
              question.choices.indices.contains(index)
        else { return nil }
        return question.choices[index]
        #else
        return nil
        #endif
    }

    /// Loads the model and the instructions it's asked with ahead of the
    /// first question, which otherwise waits for them. Call it when a screen
    /// that will show model readings appears, or earlier.
    public static func prewarm() {
        #if canImport(FoundationModels)
        RubyFoundationModelsChooser.prewarm()
        #endif
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
        for sentence in sentences(in: segments) {
            let text = segments[sentence].map(\.base).joined()
            for index in sentence where segments[index].source == .dictionary {
                let segment = segments[index]
                let range = offsets[index]..<(offsets[index] + segment.base.utf16.count)
                guard !excluded.contains(where: { $0.overlaps(range) }),
                      let choices = RubyHomographs.choices(for: segment)
                else { continue }
                result.append((index, RubyReadingQuestion(
                    sentence: text,
                    word: segment.base,
                    context: context(of: index, in: segments, within: sentence),
                    choices: choices,
                    dictionaryReading: segment.reading ?? ""
                )))
            }
        }
        return result
    }

    /// Forgets every reading the model has chosen, so `RubyText` views ask
    /// again the next time they load: to watch or measure the model, or
    /// after a system update changes it.
    public static func forgetAnswers() {
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
        for (index, question) in questions(in: segments, excluding: excluded) {
            guard let choice = await answer(question, chooser: chooser),
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

    private static func answer(_ question: RubyReadingQuestion, chooser: some RubyReadingChooser) async -> Int? {
        let key = AnswerKey(question: question, chooser: AnyHashable(chooser))
        let task = answers.withLock { answers in
            if let task = answers[key] { return task }
            if answers.count >= 1000 { answers.removeAll() }
            let task = Task { try? await chooser.choose(question) }
            answers[key] = task
            return task
        }
        let choice = await task.value
        // No answer, such as when the model refuses a sentence, keeps the
        // dictionary's reading, and isn't kept, so a later try can succeed.
        if choice == nil {
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

#if canImport(FoundationModels)
/// Asks Apple's on-device language model which meaning a word has in its
/// sentence.
///
/// Each question is its own request with a fresh session, constrained to
/// the listed meanings, with greedy sampling so the same question always
/// gets the same answer. Asking about one word at a time is slower than
/// asking about a whole sentence's at once, but more accurate: with several
/// words in one request, the model mixes up their meanings.
package struct RubyFoundationModelsChooser: RubyReadingChooser {
    package init() {}

    package static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// The session `prewarm()` loaded the model with, kept so loading
    /// isn't cancelled.
    private static let warmSession = Mutex<LanguageModelSession?>(nil)

    static func prewarm() {
        guard isAvailable else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        warmSession.withLock { $0 = session }
    }

    private static let instructions = """
        You read Japanese. Each listed word appears in the sentence and can be read \
        in more than one way, each reading with a different meaning. For each word, \
        choose the meaning that fits the sentence.
        """

    package func choose(_ question: RubyReadingQuestion) async throws -> Int? {
        guard Self.isAvailable else { return nil }
        let meanings = question.choices.map(\.meaning)
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(name: "Readings", properties: [
                DynamicGenerationSchema.Property(
                    name: "meaning",
                    description: "The meaning of \(question.word) in 「\(question.context)」",
                    schema: DynamicGenerationSchema(name: "Meaning", anyOf: meanings)
                ),
            ]),
            dependencies: []
        )
        let prompt = """
            Sentence: \(question.sentence)

            Words:
            1. \(question.word) in 「\(question.context)」: \(meanings.joined(separator: " or "))
            """
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: prompt,
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let meaning = try response.content.value(String.self, forProperty: "meaning")
        return meanings.firstIndex(of: meaning)
    }
}
#endif
