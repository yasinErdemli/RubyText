import RubyCore
import AVFoundation
import Speech

/// Prepares the shared audio session for reading aloud without blocking the
/// main thread: the category is set on a background task, and activation
/// uses the asynchronous API. macOS has no audio session to prepare.
nonisolated enum RubyAudioSession {
    static func activateForSpeech() async {
        #if os(iOS) || os(visionOS)
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback || session.mode != .spokenAudio {
                try? session.setCategory(.playback, mode: .spokenAudio)
            }
        }.value
        _ = try? await AVAudioSession.sharedInstance().activate(options: [])
        #endif
    }
}

/// Plays a recorded narration file.
nonisolated final class RubyNarrationPlayback: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var onFinish: (@Sendable () -> Void)?

    private let player: AVAudioPlayer

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    var currentTime: TimeInterval { player.currentTime }
    var duration: TimeInterval { player.duration }

    /// Call after `RubyAudioSession.activateForSpeech()`.
    func play() { player.play() }

    func pause() { player.pause() }
    func resume() { player.play() }
    func stop() { player.stop() }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}

/// Finds when each reading unit is spoken in a recording, using on-device
/// speech recognition. The recognizer may write words differently from the
/// text (我輩 for 吾輩), so recognized and expected text are compared by
/// pronunciation: both are converted to romaji and aligned letter by letter.
package nonisolated enum RubyNarrationAligner {
    enum AlignmentError: LocalizedError {
        case recognitionUnavailable
        case nothingRecognized

        var errorDescription: String? {
            switch self {
            case .recognitionUnavailable: "Japanese speech recognition isn't available on this device."
            case .nothingRecognized: "No speech was recognized in the recording."
            }
        }
    }

    /// A recognized piece of the recording.
    package struct Segment: Codable, Sendable {
        package let text: String
        package let start: Double
        package let end: Double
    }

    /// One anchor per unit, with start and end times in the recording.
    ///
    /// If a `<name>.segments.json` file sits next to the recording, its
    /// precomputed recognition results are used instead of recognizing on
    /// device. Segments describe the audio, not the text, so they stay valid
    /// when the text's markup changes.
    ///
    /// Runs off the caller's actor: recognition, and reading what's
    /// recognized, take a while.
    ///
    /// - Parameter transcriptWords: Tokenizes recognized text, to read it in
    ///   context. Passed in so this file doesn't depend on the dictionary.
    @concurrent
    static func anchors(
        for url: URL,
        units: [RubyReadingUnit],
        transcriptWords: @Sendable (String) -> [RubyWord]
    ) async throws -> [RubyTimelineAnchor] {
        let segments: [Segment]
        if let data = try? Data(contentsOf: segmentsURL(for: url)) {
            segments = try JSONDecoder().decode([Segment].self, from: data)
        } else {
            segments = try await transcribe(url)
        }
        let anchors = align(segments, to: units, transcriptWords: transcriptWords)
        guard !anchors.isEmpty else { throw AlignmentError.nothingRecognized }
        return anchors
    }

    /// Where precomputed segments for a recording are stored: `natsume.m4a`
    /// uses `natsume.segments.json`.
    package static func segmentsURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("segments.json")
    }

    // MARK: Recognition

    package static func transcribe(_ url: URL) async throws -> [Segment] {
        let japanese = Locale(identifier: "ja-JP")
        let file = try AVAudioFile(forReading: url)

        // SpeechTranscriber is more accurate where the device supports it;
        // DictationTranscriber works more widely.
        let texts: [AttributedString]
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: japanese) {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            try await installAssets(for: transcriber)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let collector = Task {
                var texts: [AttributedString] = []
                for try await result in transcriber.results { texts.append(result.text) }
                return texts
            }
            try await analyze(file, with: analyzer)
            texts = try await collector.value
        } else if let locale = await DictationTranscriber.supportedLocale(equivalentTo: japanese) {
            let transcriber = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
            try await installAssets(for: transcriber)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let collector = Task {
                var texts: [AttributedString] = []
                for try await result in transcriber.results { texts.append(result.text) }
                return texts
            }
            try await analyze(file, with: analyzer)
            texts = try await collector.value
        } else {
            throw AlignmentError.recognitionUnavailable
        }

        var segments: [Segment] = []
        for text in texts {
            for run in text.runs {
                guard let range = run.audioTimeRange else { continue }
                segments.append(Segment(
                    text: String(text[run.range].characters),
                    start: range.start.seconds,
                    end: range.end.seconds
                ))
            }
        }
        return segments.sorted { $0.start < $1.start }
    }

    private static func installAssets(for module: any SpeechModule) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    private static func analyze(_ file: AVAudioFile, with analyzer: SpeechAnalyzer) async throws {
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    // MARK: Alignment

    /// Aligns recognized segments to units and returns one anchor per unit.
    static func align(
        _ segments: [Segment],
        to units: [RubyReadingUnit],
        transcriptWords: (String) -> [RubyWord]
    ) -> [RubyTimelineAnchor] {
        // The recognized transcript, with the time span of each segment.
        var transcript = ""
        var spans: [(range: Range<Int>, start: Double, end: Double)] = []
        for segment in segments {
            let lower = transcript.utf16.count
            transcript += segment.text
            spans.append((lower..<transcript.utf16.count, segment.start, segment.end))
        }

        // Heard letters, each with the time it's spoken. Tokenizing the whole
        // transcript gives readings in context.
        var heard: [(letter: Character, time: Double, end: Double)] = []
        for word in transcriptWords(transcript) {
            let letters = phonetic(word.romaji ?? "")
            guard !letters.isEmpty else { continue }
            let start = time(at: word.range.lowerBound, in: spans)
            let end = max(time(at: word.range.upperBound, in: spans), start)
            let step = (end - start) / Double(letters.count)
            for (index, letter) in letters.enumerated() {
                let letterStart = start + step * Double(index)
                heard.append((letter, letterStart, letterStart + step))
            }
        }

        // Expected letters, each labeled with its unit.
        var expected: [(letter: Character, unit: Int)] = []
        for (index, unit) in units.enumerated() {
            for letter in phonetic(unit.romaji) { expected.append((letter, index)) }
        }
        guard !heard.isEmpty, !expected.isEmpty else { return [] }

        // Edit-distance alignment between expected and heard letters.
        let rows = expected.count + 1
        let columns = heard.count + 1
        var cost = [Int32](repeating: 0, count: rows * columns)
        for i in 0..<rows { cost[i * columns] = Int32(i) }
        for j in 0..<columns { cost[j] = Int32(j) }
        for i in 1..<rows {
            for j in 1..<columns {
                let substitution = cost[(i - 1) * columns + j - 1] + (expected[i - 1].letter == heard[j - 1].letter ? 0 : 1)
                let deletion = cost[(i - 1) * columns + j] + 1
                let insertion = cost[i * columns + j - 1] + 1
                cost[i * columns + j] = min(substitution, deletion, insertion)
            }
        }

        // Walk back through the table, recording each unit's earliest and
        // latest aligned letter times.
        var starts = [Double?](repeating: nil, count: units.count)
        var ends = [Double?](repeating: nil, count: units.count)
        var i = rows - 1
        var j = columns - 1
        while i > 0 && j > 0 {
            let here = cost[i * columns + j]
            let matches = expected[i - 1].letter == heard[j - 1].letter
            if here == cost[(i - 1) * columns + j - 1] + (matches ? 0 : 1) {
                let unit = expected[i - 1].unit
                starts[unit] = min(starts[unit] ?? heard[j - 1].time, heard[j - 1].time)
                ends[unit] = max(ends[unit] ?? heard[j - 1].end, heard[j - 1].end)
                i -= 1
                j -= 1
            } else if here == cost[(i - 1) * columns + j] + 1 {
                i -= 1
            } else {
                j -= 1
            }
        }

        // Units with no aligned letters start where the previous one ended.
        var anchors: [RubyTimelineAnchor] = []
        var previousEnd = heard.first?.time ?? 0
        for index in units.indices {
            let start = max(starts[index] ?? previousEnd, anchors.last?.start ?? 0)
            let end = max(ends[index] ?? start, start)
            anchors.append(RubyTimelineAnchor(unit: index, start: start, end: ends[index] == nil ? nil : end))
            previousEnd = end
        }
        return anchors
    }

    /// Lowercase ASCII letters of romaji, with long vowels spelled out.
    private static func phonetic(_ romaji: String) -> [Character] {
        var letters: [Character] = []
        for character in romaji.lowercased() {
            switch character {
            case "ā", "â": letters += ["a", "a"]
            case "ī", "î": letters += ["i", "i"]
            case "ū", "û": letters += ["u", "u"]
            case "ē", "ê": letters += ["e", "e"]
            case "ō", "ô": letters += ["o", "u"]
            default:
                if character.isASCII, character.isLetter { letters.append(character) }
            }
        }
        return letters
    }

    /// Time of a UTF-16 offset in the transcript, interpolated within its segment.
    private static func time(at offset: Int, in spans: [(range: Range<Int>, start: Double, end: Double)]) -> Double {
        guard let span = spans.first(where: { $0.range.contains(offset) }) ?? spans.last(where: { $0.range.lowerBound <= offset })
        else { return spans.first?.start ?? 0 }
        let length = max(span.range.count, 1)
        let fraction = min(Double(offset - span.range.lowerBound) / Double(length), 1)
        return span.start + (span.end - span.start) * fraction
    }
}
