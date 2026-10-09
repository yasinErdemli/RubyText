import Foundation
import Dictionary
import Mecab_Swift
import RubyTransliteration
import Synchronization

/// Splits Japanese text into words with readings, using MeCab and the
/// IPAdic dictionary. Its part-of-speech information also drives how words
/// group into reading phrases and how they're colored for learners.
///
/// The dictionary isn't part of RubyCore: bundle a compiled IPAdic folder
/// in your app, or download one, and pass its location to
/// `init(dictionary:)`.
public nonisolated final class RubyMeCabAnalyzer: RubyAnalyzer, @unchecked Sendable {
    private struct State {
        let recorder: PartOfSpeechRecorder
        let tokenizer: Tokenizer?
        /// Reports pronunciations (トーキョー) as readings. The package
        /// only exposes one of the two, so it's a second tagger over the
        /// same dictionary.
        let pronouncer: Tokenizer?
    }

    // MeCab's tagger isn't thread-safe, so calls are serialized. The mutex
    // also guards `recorder`.
    private let state: Mutex<State>

    /// Creates an analyzer using the compiled IPAdic dictionary in the
    /// folder at `url`: sys.dic, matrix.bin, char.bin, unk.dic and dicrc.
    ///
    /// Loading the dictionary is the expensive part, so create one
    /// analyzer and share it. If the dictionary can't be loaded, the
    /// analyzer finds no words, and text shows without readings.
    public init(dictionary url: URL) {
        let recorder = PartOfSpeechRecorder()
        let tokenizer = try? Tokenizer(dictionary: IPADicFormat(url: url, recorder: recorder))
        let pronouncer = try? Tokenizer(dictionary: IPADicFormat(url: url, pronounces: true))
        state = Mutex(State(recorder: recorder, tokenizer: tokenizer, pronouncer: pronouncer))
    }

    /// Analyzers compare by identity, since each loads its own dictionary.
    public static func == (lhs: RubyMeCabAnalyzer, rhs: RubyMeCabAnalyzer) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    /// Segments covering all of `text`. Returns only plain segments, so
    /// text shows without annotations, if the dictionary failed to load.
    public func segments(in text: String) -> [RubySegment] {
        let (annotations, ids, pronunciations) = state.withLock { state in
            let recorder = state.recorder
            recorder.ids.removeAll(keepingCapacity: true)
            let annotations = state.tokenizer?.tokenize(text: text, transliteration: .katakana) ?? []
            // MeCab reports one ID per node: the sentence start, each token,
            // and the sentence end. If tokens were dropped (surface not found
            // in the text) the IDs can't be matched up, so go without them.
            let ids: [UInt16]? = recorder.ids.count == annotations.count + 2
                ? Array(recorder.ids.dropFirst().dropLast())
                : nil
            // Same dictionary, so the same tokens; check before pairing them.
            let spoken = state.pronouncer?.tokenize(text: text, transliteration: .katakana) ?? []
            let pronunciations: [String]? = spoken.map(\.base) == annotations.map(\.base)
                ? spoken.map(\.reading)
                : nil
            return (annotations, ids, pronunciations)
        }

        var segments: [RubySegment] = []
        var cursor = text.startIndex
        for (index, annotation) in annotations.enumerated() {
            // Text between tokens (MeCab skipped it, or none were found)
            // becomes plain segments, so segments always cover the text.
            if cursor < annotation.range.lowerBound {
                segments.append(RubySegment(String(text[cursor..<annotation.range.lowerBound]), source: .dictionary))
            }
            cursor = annotation.range.upperBound

            let token = String(text[annotation.range])
            let isJapanese = token.contains(where: RubyKana.isJapanese)
            // Keep numbers and Latin words such as 2026 or iPhone: they're
            // spoken, so they take part in reading phrases and read-aloud
            // timing, but they get no readings. Skip punctuation.
            guard isJapanese || token.contains(where: { $0.isLetter || $0.isNumber }) else {
                segments.append(RubySegment(token, source: .dictionary))
                continue
            }

            // Unknown words come back with their surface as the reading.
            let katakana = annotation.reading
            let hasReading = isJapanese && !katakana.isEmpty && !katakana.contains(where: RubyKana.isKanji)
            let id = ids?[index]
            let reading = hasReading ? RubyKana.hiragana(katakana) : nil
            let pronunciation = hasReading ? pronunciations.map { RubyKana.hiragana($0[index]) } : nil
            // IPAdic writes * for words without a dictionary form.
            let dictionaryForm = annotation.dictionaryForm == "*" ? token : annotation.dictionaryForm

            segments.append(RubySegment(
                token,
                reading: reading,
                pronunciation: pronunciation,
                word: RubySegment.Word(
                    partOfSpeech: id.map(Self.partOfSpeech),
                    dictionaryForm: dictionaryForm,
                    attachesToPrevious: id.map(Self.attaches) ?? (annotation.partOfSpeech == .particle)
                ),
                source: .dictionary
            ))
        }
        if cursor < text.endIndex {
            segments.append(RubySegment(String(text[cursor...]), source: .dictionary))
        }
        return segments
    }

    // MARK: IPAdic part-of-speech IDs (pos-id.def)

    /// IDs of words that attach to the previous word in a reading phrase:
    /// particles, auxiliaries, and suffixes (吾輩|は, 生まれ|た, し|て|い|ます,
    /// 2026|年).
    private static let attachingIDs: Set<UInt16> = [
        11, 12,             // 形容詞, 接尾 / 非自立 (〜やすい, 〜にくい)
        13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, // 助詞, particles
        25,                 // 助動詞, auxiliaries (です, ます, た)
        32, 33,             // 動詞, 接尾 / 非自立 (〜れる, いる in している)
        50, 51, 52, 53, 54, 55, 56, 57, 58, // 名詞, 接尾, noun suffixes (さん, 円, 年)
    ]

    private static func attaches(_ id: UInt16) -> Bool {
        attachingIDs.contains(id)
    }

    private static func partOfSpeech(_ id: UInt16) -> RubyPartOfSpeech {
        switch id {
        case 0...2: .interjection     // その他,間投 / フィラー / 感動詞
        case 10...12: .adjective      // 形容詞
        case 13...24: .particle       // 助詞
        case 25: .auxiliary           // 助動詞
        case 26: .conjunction         // 接続詞
        case 27...30: .prefix         // 接頭詞
        case 31...33: .verb           // 動詞
        case 34, 35: .adverb          // 副詞
        // な-adjective and ない-adjective stems are nouns to IPAdic, but
        // learners know them as adjectives (静か, 綺麗).
        case 37, 40, 52, 64: .adjective
        case 36...67: .noun           // 名詞
        case 68: .adnominal           // 連体詞
        default: .other               // 記号 and anything else
        }
    }
}

/// Collects the IPAdic part-of-speech ID of each node MeCab produces, in
/// order. The package's `Annotation` only exposes a coarse `PartOfSpeech`
/// without auxiliaries, conjunctions, or adjective stems.
private nonisolated final class PartOfSpeechRecorder {
    var ids: [UInt16] = []
}

/// Where IPAdic keeps each feature, and how MeCab should report a word's
/// part of speech.
private nonisolated struct IPADicFormat: DictionaryProviding {
    let url: URL
    /// Collects part-of-speech IDs as the tokenizer asks for them.
    var recorder: PartOfSpeechRecorder?
    /// Reports pronunciations (トーキョー) in place of readings (トウキョウ).
    var pronounces = false

    var readingIndex: Int { pronounces ? pronunciationIndex : 7 }
    var pronunciationIndex: Int { 8 }
    var dictionaryFormIndex: Int { 6 }

    func partOfSpeech(posID: UInt16) -> PartOfSpeech {
        recorder?.ids.append(posID)
        // Reported when the recorded IDs can't be used.
        switch posID {
        case 11...25, 32...33, 50...58: return .particle
        case 3...9: return .symbol
        case 27...30: return .prefix
        case 31: return .verb
        case 34...35: return .adverb
        case 36...67: return .noun
        default: return .unknown
        }
    }
}
