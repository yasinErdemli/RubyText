import Foundation
import RubyTransliteration
import SQLite3
import Synchronization

/// English definitions of Japanese words, from a JMdict database.
///
/// The database isn't part of RubyCore. Add the RubyJMdict product and use
/// `.jmdict`, or open a copy your app downloads with `init(url:)`.
/// Tools/build-dictionary.py builds one.
///
/// JMdict is the work of the Electronic Dictionary Research and
/// Development Group (https://www.edrdg.org/jmdict/j_jmdict.html), used
/// under CC BY-SA 4.0. Apps showing its definitions must credit it;
/// `RubyDictionary.credit` has suitable wording.
public nonisolated final class RubyDictionary: Sendable {

    /// Attribution the JMdict license requires wherever definitions show.
    public static let credit = "Definitions from JMdict, © Electronic Dictionary Research and Development Group, CC BY-SA 4.0."

    /// One dictionary entry: a word with its spellings, readings, and senses.
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: Int
        /// Kanji spellings, most usual first; empty for kana-only words.
        public let spellings: [String]
        public let readings: [String]
        /// Whether the word is in JMdict's common vocabulary.
        public let isCommon: Bool
        /// How many of the senses are usually written in kana, like 居る
        /// as いる.
        public let kanaSenseCount: Int
        public let senses: [Sense]

        /// Whether the word is usually written in kana.
        public var isUsuallyKana: Bool { kanaSenseCount > 0 }
    }

    public struct Sense: Hashable, Sendable {
        /// Labels such as "Ichidan verb", "Transitive", or "な-adjective".
        public let partsOfSpeech: [String]
        /// JMdict's part-of-speech codes, such as "v1" or "prt".
        public let partOfSpeechCodes: [String]
        public let glosses: [String]
    }

    // A SQLite connection mustn't be used from two threads at once, so
    // queries are serialized through the mutex.
    private let database: Mutex<OpaquePointer?>
    private let tagDescriptions: [String: String]

    /// Opens the dictionary database at `url`, read only, or returns
    /// `nil` if it can't be opened.
    public init?(url: URL) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        var tags: [String: String] = [:]
        Self.query(database, "SELECT code, description FROM tags", bindings: []) { row in
            tags[Self.text(row, 0)] = Self.text(row, 1)
        }
        tagDescriptions = tags
        self.database = Mutex(database)
    }

    deinit {
        _ = database.withLock { sqlite3_close($0) }
    }

    /// Entries for a word, best match first.
    ///
    /// - Parameters:
    ///   - terms: Forms to look up, in order of preference, such as the
    ///     dictionary form and then the word as written. The first form
    ///     with entries is used.
    ///   - reading: The word's reading in context, used to choose between
    ///     entries spelled alike, such as 生 read なま or せい.
    ///   - partOfSpeech: The word's role in context, used to choose
    ///     between homophones, such as the particle は and 歯 (tooth).
    package func entries(
        for terms: [String],
        reading: String? = nil,
        partOfSpeech: RubyPartOfSpeech? = nil,
        limit: Int = 3
    ) -> [Entry] {
        database.withLock { database in
            entries(in: database, for: terms, reading: reading, partOfSpeech: partOfSpeech, limit: limit)
        }
    }

    private func entries(
        in database: OpaquePointer?,
        for terms: [String],
        reading: String?,
        partOfSpeech: RubyPartOfSpeech?,
        limit: Int
    ) -> [Entry] {
        for term in terms where !term.isEmpty {
            var found: [Entry] = []
            Self.query(database, """
                SELECT e.id, e.common, e.usually_kana, e.kanji, e.kana, e.senses FROM forms f
                JOIN entries e ON e.id = f.entry
                WHERE f.text = ?
                ORDER BY f.common DESC, e.common DESC
                LIMIT 60
                """, bindings: [term]) { row in
                found.append(entry(from: row))
            }
            guard !found.isEmpty else { continue }
            let reading = reading.map(RubyKana.hiragana)
            let termIsKana = term.allSatisfy { RubyKana.isJapanese($0) && !RubyKana.isKanji($0) }
            // Rank by, in order: a matching part of speech; a matching
            // reading, as the main reading, as another, or sharing the stem
            // of an inflected form (うまれた, うまれる); and, for kana, words
            // usually written in kana. Ties keep the database order, common
            // words first.
            func score(_ entry: Entry) -> Int {
                var score = 0
                if let partOfSpeech, entry.senses.contains(where: { Self.matches($0, partOfSpeech) }) {
                    score += 4000
                }
                if let reading {
                    score += entry.readings.map(RubyKana.hiragana).enumerated().map { index, candidate in
                        candidate == reading ? (index == 0 ? 1000 : 800) : candidate.commonPrefix(with: reading).count
                    }.max() ?? 0
                }
                if termIsKana {
                    score += 150 * min(entry.kanaSenseCount, 3)
                }
                return score
            }
            let ranked = found.enumerated().sorted { lhs, rhs in
                let (left, right) = (score(lhs.element), score(rhs.element))
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            return ranked.prefix(limit).map(\.element)
        }
        return []
    }

    private func entry(from row: OpaquePointer) -> Entry {
        let senses = (try? JSONSerialization.jsonObject(with: Data(Self.text(row, 5).utf8))) as? [[Any]] ?? []
        return Entry(
            id: Int(sqlite3_column_int64(row, 0)),
            spellings: Self.list(Self.text(row, 3)),
            readings: Self.list(Self.text(row, 4)),
            isCommon: sqlite3_column_int(row, 1) != 0,
            kanaSenseCount: Int(sqlite3_column_int(row, 2)),
            senses: senses.compactMap { sense in
                guard sense.count == 2, let tags = sense[0] as? [String], let glosses = sense[1] as? [String] else { return nil }
                return Sense(partsOfSpeech: tags.map(label), partOfSpeechCodes: tags, glosses: glosses)
            }
        )
    }

    /// Short labels for common part-of-speech codes, in the terms learners
    /// are taught.
    private static let labels: [String: String] = [
        "n": "Noun",
        "pn": "Pronoun",
        "adj-i": "い-adjective",
        "adj-ix": "い-adjective (いい/よい)",
        "adj-na": "な-adjective",
        "adj-no": "Noun taking の",
        "adj-pn": "Pre-noun adjectival",
        "adv": "Adverb",
        "adv-to": "Adverb taking と",
        "vi": "Intransitive",
        "vt": "Transitive",
        "vs": "Takes する",
        "vs-i": "する verb",
        "vk": "くる verb",
        "v5k-s": "Godan verb (行く)",
        "prt": "Particle",
        "aux-v": "Auxiliary verb",
        "aux-adj": "Auxiliary adjective",
        "cop": "Copula",
        "int": "Interjection",
        "exp": "Expression",
        "ctr": "Counter",
    ]

    /// A label for a part-of-speech code: a short one for common codes,
    /// otherwise JMdict's description without romanized Japanese terms,
    /// such as "Godan verb with 'ru' ending".
    private func label(for code: String) -> String {
        if let label = Self.labels[code] { return label }
        var description = tagDescriptions[code] ?? code
        // Drop trailing terms like "(keiyoushi)".
        while let range = description.range(of: #"\s*\([a-z]+\)$"#, options: .regularExpression) {
            description.removeSubrange(range)
        }
        return description.prefix(1).uppercased() + description.dropFirst()
    }

    /// Whether a sense's JMdict part of speech fits MeCab's.
    private static func matches(_ sense: Sense, _ partOfSpeech: RubyPartOfSpeech) -> Bool {
        let prefixes: [String] = switch partOfSpeech {
        case .noun: ["n", "pn", "num"]
        case .verb: ["v"]
        case .adjective: ["adj-i", "adj-na", "adj-ix", "adj-no"]
        case .adverb: ["adv"]
        case .particle: ["prt"]
        case .auxiliary: ["aux", "cop"]
        case .adnominal: ["adj-pn"]
        case .conjunction: ["conj"]
        case .prefix: ["pref"]
        case .interjection: ["int"]
        case .other: []
        }
        return sense.partOfSpeechCodes.contains { code in
            prefixes.contains { code == $0 || code.hasPrefix($0 + "-") || (code.hasPrefix($0) && $0 == "v") }
        }
    }

    // MARK: SQLite

    private static func query(_ database: OpaquePointer?, _ sql: String, bindings: [String], row: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        // SQLITE_TRANSIENT: SQLite copies the string.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }

    private static func text(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }

    private static func list(_ joined: String) -> [String] {
        joined.split(separator: "、").map(String.init)
    }
}

extension RubyDictionary {
    /// Entries for `word`, best match first: the entry whose reading
    /// matches the one shown, so 人気 read ひとけ finds "human presence".
    /// Looks up the dictionary form, then the word as written, then its
    /// reading.
    public func entries(for word: RubyWordInfo, limit: Int = 3) -> [Entry] {
        var terms = [word.dictionaryForm, word.text, word.reading].compactMap { $0 }
        // JMdict lists 勉強する under the noun 勉強.
        if let dictionaryForm = word.dictionaryForm, dictionaryForm.hasSuffix("する"), dictionaryForm.count > 2 {
            terms.append(String(dictionaryForm.dropLast(2)))
        }
        return entries(for: terms, reading: word.reading, partOfSpeech: word.partOfSpeech, limit: limit)
    }
}
