import Foundation
import Dictionary
import Mecab_Swift
import RubyCore
import RubyTransliteration
import Synchronization

/// Splits Japanese text into words with readings, using MeCab and a
/// dictionary in IPAdic's or UniDic's format. Its part-of-speech
/// information also drives how words group into reading phrases and how
/// they're colored for learners.
///
/// The dictionary isn't part of RubyText. Use the IPAdic that
/// Mecab-Swift's `IPADic` product provides, or bundle or download a
/// compiled IPAdic or UniDic folder, and pass its location to
/// `init(dictionary:)`, which tells the two apart by their `dicrc`.
///
/// IPAdic is small, about 50 MB, but hasn't changed since 2007. UniDic is
/// maintained by the National Institute for Japanese Language and
/// Linguistics and knows more recent words, but is larger: about 250 MB
/// for UniDic 2.1.2, and 770 MB for UniDic 3.1. For another dictionary or
/// analyzer, write your own `RubyAnalyzer`.
public nonisolated final class RubyMeCabAnalyzer: RubyAnalyzer, Sendable {
    /// The formats of dictionary MeCab reads, which say where each word's
    /// reading and grammar are.
    public enum Format: Hashable, Sendable {
        /// IPAdic, and dictionaries built on it.
        case ipadic
        /// UniDic, version 2.1.2 or later.
        case unidic
    }

    /// The format of the dictionary, read from its `dicrc` file.
    public let format: Format

    /// MeCab's taggers, each reporting different features of the same
    /// tokens: Mecab-Swift exposes two features per tagger.
    private enum Taggers {
        case ipadic(IPADicTaggers)
        case unidic(UniDicTaggers)
    }

    private struct IPADicTaggers {
        let recorder: PartOfSpeechRecorder
        /// Readings and dictionary forms, with part-of-speech IDs.
        let tokenizer: Tokenizer
        /// Pronunciations (トーキョー).
        let pronouncer: Tokenizer?
    }

    private struct UniDicTaggers {
        /// Readings (kana) and dictionary forms (orthBase).
        let tokenizer: Tokenizer
        /// Pronunciations (pron) and the main part of speech (pos1).
        let pronouncer: Tokenizer
        /// The part of speech's subcategory (pos2), and the feature after
        /// kana, where kana is for words whose features hold a comma.
        let grammar: Tokenizer
    }

    // MeCab's tagger isn't thread-safe, so calls are serialized. The mutex
    // also guards IPAdic's `recorder`.
    private let taggers: Mutex<Taggers?>

    /// Creates an analyzer using the compiled IPAdic or UniDic dictionary
    /// in the folder at `url`: sys.dic, matrix.bin, char.bin, unk.dic and
    /// dicrc.
    ///
    /// Loading the dictionary is the expensive part, so create one
    /// analyzer and share it. If the dictionary can't be loaded, the
    /// analyzer finds no words, and text shows without readings.
    public init(dictionary url: URL) {
        let dicrc = (try? Data(contentsOf: url.appending(path: "dicrc"))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        if let layout = UniDicLayout(dicrc: dicrc) {
            format = .unidic
            let taggers: UniDicTaggers? = if
                let tokenizer = try? Tokenizer(dictionary: FeatureFormat(url: url, readingIndex: layout.kana, dictionaryFormIndex: layout.orthBase)),
                let pronouncer = try? Tokenizer(dictionary: FeatureFormat(url: url, readingIndex: layout.pron, dictionaryFormIndex: layout.pos1)),
                let grammar = try? Tokenizer(dictionary: FeatureFormat(url: url, readingIndex: layout.pos2, dictionaryFormIndex: layout.kana + 1)) {
                UniDicTaggers(tokenizer: tokenizer, pronouncer: pronouncer, grammar: grammar)
            } else {
                nil
            }
            self.taggers = Mutex(taggers.map(Taggers.unidic))
        } else {
            format = .ipadic
            let recorder = PartOfSpeechRecorder()
            let tokenizer = try? Tokenizer(dictionary: IPADicFormat(url: url, recorder: recorder))
            let pronouncer = try? Tokenizer(dictionary: IPADicFormat(url: url, pronounces: true))
            self.taggers = Mutex(tokenizer.map { .ipadic(IPADicTaggers(recorder: recorder, tokenizer: $0, pronouncer: pronouncer)) })
        }
    }

    /// Analyzers compare by identity, since each loads its own dictionary.
    public static func == (lhs: RubyMeCabAnalyzer, rhs: RubyMeCabAnalyzer) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    /// What MeCab says about a token, from all its taggers.
    private struct Token {
        let annotation: Annotation
        /// The reading, in katakana, if the dictionary has one.
        let reading: String?
        /// The pronunciation, in katakana, if the taggers agreed.
        let pronunciation: String?
        let word: RubySegment.Word
    }

    /// Segments covering all of `text`. Returns only plain segments, so
    /// text shows without annotations, if the dictionary failed to load.
    public func segments(in text: String) -> [RubySegment] {
        let tokens: [Token] = taggers.withLock { taggers in
            switch taggers {
            case .ipadic(let taggers): Self.tokens(in: text, with: taggers)
            case .unidic(let taggers): Self.tokens(in: text, with: taggers)
            case nil: []
            }
        }

        var segments: [RubySegment] = []
        var cursor = text.startIndex
        for token in tokens {
            let annotation = token.annotation
            // Text between tokens (MeCab skipped it, or none were found)
            // becomes plain segments, so segments always cover the text.
            if cursor < annotation.range.lowerBound {
                segments.append(RubySegment(String(text[cursor..<annotation.range.lowerBound]), source: .dictionary))
            }
            cursor = annotation.range.upperBound

            let base = String(text[annotation.range])
            let isJapanese = base.contains(where: \.isJapanese)
            // Keep numbers and Latin words such as 2026 or iPhone: they're
            // spoken, so they take part in reading phrases and read-aloud
            // timing, but they get no readings. Skip punctuation.
            guard isJapanese || base.contains(where: { $0.isLetter || $0.isNumber }) else {
                segments.append(RubySegment(base, source: .dictionary))
                continue
            }

            // IPAdic reads 分の as one word, ぶんの, as in fractions (三分の
            // 一), though before most words it's minutes (5分の休憩). Split,
            // the number rules tell them apart.
            if base == "分の" {
                segments.append(RubySegment("分", reading: "ぶん", word: RubySegment.Word(
                    partOfSpeech: .noun, dictionaryForm: "分", attachesToPrevious: true
                ), source: .dictionary))
                segments.append(RubySegment("の", reading: "の", word: RubySegment.Word(
                    partOfSpeech: .particle, dictionaryForm: "の", attachesToPrevious: true
                ), source: .dictionary))
                continue
            }
            let reading = isJapanese ? token.reading : nil
            segments.append(RubySegment(
                base,
                reading: reading.map(RubyKana.hiragana),
                pronunciation: reading == nil ? nil : token.pronunciation.map(RubyKana.hiragana),
                word: token.word,
                source: .dictionary
            ))
        }
        if cursor < text.endIndex {
            segments.append(RubySegment(String(text[cursor...]), source: .dictionary))
        }
        return segments
    }


    // MARK: IPAdic

    private static func tokens(in text: String, with taggers: IPADicTaggers) -> [Token] {
        let recorder = taggers.recorder
        recorder.ids.removeAll(keepingCapacity: true)
        let annotations = taggers.tokenizer.tokenize(text: text, transliteration: .katakana)
        // MeCab reports one ID per node: the sentence start, each token,
        // and the sentence end. If tokens were dropped (surface not found
        // in the text) the IDs can't be matched up, so go without them.
        let ids: [UInt16]? = recorder.ids.count == annotations.count + 2
            ? Array(recorder.ids.dropFirst().dropLast())
            : nil
        // Same dictionary, so the same tokens; check before pairing them.
        let spoken = taggers.pronouncer?.tokenize(text: text, transliteration: .katakana) ?? []
        let pronunciations: [String]? = spoken.map(\.base) == annotations.map(\.base)
            ? spoken.map(\.reading)
            : nil

        return annotations.enumerated().map { index, annotation in
            let id = ids?[index]
            // IPAdic writes * for the dictionary form of words it doesn't
            // know, whose reading is their surface, as they're spoken or
            // not, and whose part of speech is a guess from their script:
            // ｶﾞｯｺｳ isn't the name of an organization.
            let isKnown = annotation.dictionaryForm != "*"
            let dictionaryForm = isKnown ? annotation.dictionaryForm : annotation.base
            // Unknown words come back with their surface as the reading,
            // which only counts if it has no kanji.
            let isReading = { (feature: String) in !feature.isEmpty && !feature.contains(where: \.isKanji) }
            return Token(
                annotation: annotation,
                reading: isReading(annotation.reading) ? annotation.reading : nil,
                pronunciation: isKnown ? pronunciations.map { $0[index] }.flatMap { isReading($0) ? $0 : nil } : nil,
                word: RubySegment.Word(
                    partOfSpeech: id.map(Self.partOfSpeech),
                    dictionaryForm: dictionaryForm,
                    attachesToPrevious: id.map(Self.attaches) ?? (annotation.partOfSpeech == .particle),
                    isProperNoun: isKnown && id.map(Self.properNounIDs.contains) ?? false
                )
            )
        }
    }

    // IPAdic part-of-speech IDs (pos-id.def).

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

    /// IDs of names: 名詞, 固有名詞 (general, people, organizations,
    /// places, countries).
    private static let properNounIDs: ClosedRange<UInt16> = 41...47

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

    // MARK: UniDic

    private static func tokens(in text: String, with taggers: UniDicTaggers) -> [Token] {
        let annotations = taggers.tokenizer.tokenize(text: text, transliteration: .katakana)
        // Same dictionary, so the same tokens; check before pairing them.
        let spoken = taggers.pronouncer.tokenize(text: text, transliteration: .katakana)
        let grammar = taggers.grammar.tokenize(text: text, transliteration: .katakana)
        let bases = annotations.map(\.base)
        let paired = spoken.map(\.base) == bases && grammar.map(\.base) == bases

        // Readings are in katakana, and * for none. Unknown words come back
        // with their surface, which counts if it's kana.
        func kana(_ feature: String) -> String? {
            !feature.isEmpty && feature.allSatisfy { $0.isKatakana || $0.isHiragana } ? feature : nil
        }
        var tokens: [Token] = []
        var previous: (pos1: String, base: String)?
        for (index, annotation) in annotations.enumerated() {
            guard paired else {
                tokens.append(Token(
                    annotation: annotation,
                    reading: kana(annotation.reading),
                    pronunciation: nil,
                    word: RubySegment.Word(dictionaryForm: annotation.dictionaryForm)
                ))
                continue
            }
            let pos1 = spoken[index].dictionaryForm
            let pos2 = grammar[index].reading
            // Mecab-Swift splits features at every comma, even inside a
            // quoted one, as UniDic 3 has before kana for a few words (日,
            // 年, 家族). With one, the kana are a feature later, and the
            // feature in their place is a word type in kanji (体). With
            // more, the pronunciation is the reading where it has no long
            // vowels, which it would write differently (トーキョー).
            let pronunciation = kana(spoken[index].reading)
            let reading = kana(annotation.reading)
                ?? kana(grammar[index].dictionaryForm)
                ?? pronunciation.flatMap { $0.contains("ー") ? nil : $0 }
            tokens.append(Token(
                annotation: annotation,
                reading: reading,
                pronunciation: pronunciation,
                word: RubySegment.Word(
                    partOfSpeech: partOfSpeech(pos1: pos1, pos2: pos2),
                    dictionaryForm: annotation.dictionaryForm == "*" ? annotation.base : annotation.dictionaryForm,
                    attachesToPrevious: attaches(pos1: pos1, pos2: pos2, after: previous),
                    isProperNoun: pos1 == "名詞" && pos2 == "固有名詞"
                )
            ))
            previous = (pos1, annotation.base)
        }
        return tokens
    }

    /// The part of speech of a UniDic word, in the categories learners are
    /// taught.
    private static func partOfSpeech(pos1: String, pos2: String) -> RubyPartOfSpeech {
        switch pos1 {
        case "名詞", "代名詞": .noun
        case "動詞": .verb
        // 形状詞 are な-adjective stems (静か, 綺麗).
        case "形容詞", "形状詞": .adjective
        case "副詞": .adverb
        case "助詞": .particle
        case "助動詞": .auxiliary
        case "連体詞": .adnominal
        case "接続詞": .conjunction
        case "接頭辞": .prefix
        case "感動詞": .interjection
        case "接尾辞":
            switch pos2 {
            case "動詞的": .verb
            case "形容詞的", "形状詞的": .adjective
            default: .noun
            }
        default: .other
        }
    }

    /// Whether a UniDic word attaches to the one before it in a reading
    /// phrase: particles, auxiliaries and suffixes (吾輩|は, 生まれ|た,
    /// 田中|さん), and verbs and adjectives that can follow another (し|て|
    /// いる, 読ま|なく|ない).
    ///
    /// UniDic marks those verbs and adjectives as able to follow another
    /// (非自立可能) whether or not they do, so they attach only after a
    /// verb, adjective, auxiliary, or て: いる in している, but not in 家に
    /// いる.
    private static func attaches(pos1: String, pos2: String, after previous: (pos1: String, base: String)?) -> Bool {
        switch pos1 {
        case "助詞", "助動詞", "接尾辞":
            return true
        case "形状詞":
            // そう in 降りそう, よう in ような.
            return pos2 == "助動詞語幹"
        case "動詞", "形容詞":
            guard pos2 == "非自立可能", let previous else { return false }
            return ["動詞", "形容詞", "助動詞"].contains(previous.pos1)
                || previous.pos1 == "助詞" && ["て", "で"].contains(previous.base)
        default:
            return false
        }
    }
}

/// Where UniDic keeps the features RubyText reads, which moved between
/// versions: its kana reading is feature 17 in UniDic 2.1.2 and 20 from
/// 2.2 on.
private nonisolated struct UniDicLayout {
    var pos1 = 0
    var pos2 = 1
    var pron = 9
    var orthBase = 10
    var kana: Int

    /// The layout `dicrc` describes, or `nil` if it isn't UniDic's.
    ///
    /// Reads the list of features in its comments where it has one
    /// (`; f[17]: kana`), and otherwise the output format it names.
    init?(dicrc: String) {
        guard dicrc.localizedCaseInsensitiveContains("unidic") else { return nil }
        var fields: [String: Int] = [:]
        for match in dicrc.matches(of: #/f\[(\d+)\]:\s*(\w+)/#) {
            if let index = Int(match.output.1) { fields[String(match.output.2)] = index }
        }
        // UniDic 2.1.2 names its format unidic; later versions unidic22.
        let isVersion2_1 = dicrc.contains(#/output-format-type\s*=\s*unidic\s*$/#.anchorsMatchLineEndings())
        kana = fields["kana"] ?? (isVersion2_1 ? 17 : 20)
        pos1 = fields["pos1"] ?? pos1
        pos2 = fields["pos2"] ?? pos2
        pron = fields["pron"] ?? pron
        orthBase = fields["orthBase"] ?? orthBase
    }
}

/// A dictionary whose tagger reports the features at two indices as each
/// token's reading and dictionary form.
private nonisolated struct FeatureFormat: DictionaryProviding {
    let url: URL
    let readingIndex: Int
    let dictionaryFormIndex: Int
    var pronunciationIndex: Int { readingIndex }

    func partOfSpeech(posID: UInt16) -> PartOfSpeech { .unknown }
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
