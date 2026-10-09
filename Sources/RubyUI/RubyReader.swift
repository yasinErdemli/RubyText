import RubyCore
import SwiftUI
import AVFoundation
import Synchronization

/// Reads Japanese text aloud and tracks the phrase being spoken, so
/// `RubyText` views attached with `rubyReader(_:)` can emphasize it.
///
///     @State private var reader = RubyReader(analyzer: analyzer)
///
///     RubyText(text).rubyReader(reader)
///     Button("Read Aloud") { reader.speak(text) }
///
/// It emphasizes reading phrases (文節) such as 吾輩は rather than single
/// words, because voices pronounce particles together with the word before
/// them.
///
/// Two sources are supported:
/// - `speak(_:)` synthesizes speech. Japanese voices only time whole phrases
///   and report them in bursts, so the reader renders the speech itself,
///   plays it through `AVAudioEngine`, and divides each timed stretch among
///   its phrases by their length in moras.
/// - `play(narration:for:)` plays a recording and finds when each phrase is
///   spoken with on-device speech recognition.
@Observable
public final class RubyReader {
    /// Finds the words and phrases to emphasize, if anything does. Use the
    /// same analyzer as the `RubyText` views showing the text.
    public let analyzer: (any RubyAnalyzer)?
    /// Speech rate relative to the system default, from 0.5 (slow) to 2.
    /// Applies to synthesized speech.
    public var rate: Float = 1
    /// Identifier of the voice to read with, or `nil` for the best-quality
    /// Japanese voice installed. See `japaneseVoices`.
    public var voiceIdentifier: String?
    /// Which readings synthesized speech says in place of the text as
    /// written, as `rubySpokenReadings(_:)` sets for VoiceOver: by
    /// default, the ones a voice is most likely to get wrong, so
    /// {宇宙|そら} is read そら.
    public var spokenReadings = RubySpokenReadings.corrections

    /// Installed Japanese voices, best quality first. People can download
    /// Enhanced and Premium voices in Settings › Accessibility.
    public static var japaneseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") }
            .sorted { lhs, rhs in
                lhs.quality != rhs.quality ? lhs.quality.rawValue > rhs.quality.rawValue : lhs.name < rhs.name
            }
    }

    public private(set) var isSpeaking = false
    public private(set) var isPaused = false
    /// Whether a recording is being aligned to its text before playing.
    public private(set) var isPreparing = false
    /// The text being read, with `{base|reading}` markup removed.
    public private(set) var text: String?

    /// The phrase being spoken right now.
    struct SpokenWord {
        /// UTF-16 range of the phrase in `text`.
        let range: Range<Int>
        /// Fraction of the phrase spoken so far.
        let progress: Double
        /// Seconds since the phrase started.
        let elapsed: TimeInterval
    }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var speech: RubySpeechPlayback?
    @ObservationIgnored private var narration: RubyNarrationPlayback?
    @ObservationIgnored private var narrationAnchors: [RubyTimelineAnchor] = []
    @ObservationIgnored private var units: [RubyReadingUnit] = []
    /// The text synthesized speech is reading, with readings in place of
    /// their words, which its markers are offsets in.
    @ObservationIgnored private var spokenString: RubySpokenString?
    /// Increments on every start or stop, so stale async work is ignored.
    @ObservationIgnored private var session = 0
    /// Alignments already computed, keyed by recording and text.
    @ObservationIgnored private var alignments: [String: [RubyTimelineAnchor]] = [:]
    /// Whether reading paused because of an audio interruption, such as a
    /// phone call, so it can resume when the interruption ends.
    @ObservationIgnored private var pausedByInterruption = false
    /// Interruption observations; they end when the tokens are released.
    @ObservationIgnored private var interruptionObservers: [NotificationCenter.ObservationToken] = []
    @ObservationIgnored private var routeChangeObserver: Task<Void, Never>?

    /// Creates a reader that finds the phrases to emphasize with
    /// `analyzer`, the one your `RubyText` views use.
    public convenience init(analyzer: some RubyAnalyzer) {
        self.init(analyzer as any RubyAnalyzer)
    }

    /// Creates a reader with no analyzer, which reads text aloud but
    /// can't find phrases in it to emphasize.
    public convenience init() {
        self.init(nil)
    }

    private init(_ analyzer: (any RubyAnalyzer)?) {
        self.analyzer = analyzer
        #if os(iOS)
        interruptionObservers = [
            NotificationCenter.default.addObserver(for: AVAudioSession.DidBecomeInactiveMessage.self) { [weak self] message in
                guard case .systemInterruption = message.deactivationResult else { return }
                self?.interruptionBegan()
            },
            NotificationCenter.default.addObserver(for: AVAudioSession.ResumptionRecommendationMessage.self) { [weak self] message in
                self?.interruptionEnded(shouldResume: message.recommendation == .shouldResume)
            },
        ]
        routeChangeObserver = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self else { return }
                handleRouteChange(notification)
            }
        }
        #endif
    }

    isolated deinit {
        routeChangeObserver?.cancel()
    }

    // MARK: Synthesized speech

    /// Starts reading `markup` aloud, replacing anything being read.
    public func speak(_ markup: String) {
        stop()
        let content = RubyContent.content(for: markup, analyzer: analyzer)
        // The readings themselves, rather than SSML, which voices may
        // ignore and which turns off the rate.
        let spoken = content.spokenString(spokenReadings)
        let utterance = AVSpeechUtterance(string: spoken.string)
        utterance.voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? Self.japaneseVoices.first
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = min(
            max(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )

        let speech = RubySpeechPlayback()
        speech.onFinish = Self.finishHandler(for: self, session: session + 1)
        self.speech = speech
        begin(content)
        spokenString = spoken

        let token = session
        Task {
            await RubyAudioSession.activateForSpeech()
            // Something else started or stopped meanwhile.
            guard token == session else { return }
            synthesizer.write(
                utterance,
                toBufferCallback: speech.receive(buffer:),
                toMarkerCallback: speech.receive(markers:)
            )
        }
    }

    // MARK: Recorded narration

    /// Plays a recording of `markup` read aloud, emphasizing along with it.
    ///
    /// The first time, the recording is aligned to the text with on-device
    /// speech recognition, which can take a moment; results are cached.
    public func play(narration url: URL, for markup: String) async throws {
        stop()
        let content = RubyContent.content(for: markup, analyzer: analyzer)
        let units = RubyReadingUnits.units(in: content.string, words: content.words)
        let key = url.absoluteString + "\n" + content.string
        let token = session

        let anchors: [RubyTimelineAnchor]
        if let cached = alignments[key] {
            anchors = cached
        } else {
            isPreparing = true
            defer { isPreparing = false }
            let analyzer = analyzer
            anchors = try await RubyNarrationAligner.anchors(for: url, units: units) {
                RubyContent.words(from: RubyContent.segments(in: $0, analyzer: analyzer))
            }
            alignments[key] = anchors
        }
        // Creating the player touches the audio session, so do it off the
        // main thread, then activate the session asynchronously.
        let narration = try await Task.detached(priority: .userInitiated) {
            try RubyNarrationPlayback(url: url)
        }.value
        await RubyAudioSession.activateForSpeech()
        // Something else started or stopped meanwhile.
        guard token == session else { return }

        narration.onFinish = Self.finishHandler(for: self, session: session + 1)
        self.narration = narration
        narrationAnchors = anchors
        begin(content)
        narration.play()
    }

    // MARK: Controls

    public func pause() {
        guard isSpeaking, !isPaused else { return }
        speech?.pause()
        narration?.pause()
        isPaused = true
        pausedByInterruption = false
    }

    public func resume() {
        guard isSpeaking, isPaused else { return }
        isPaused = false
        pausedByInterruption = false
        let token = session
        Task {
            // An interruption deactivates the session, so activate it again.
            await RubyAudioSession.activateForSpeech()
            guard token == session, !isPaused else { return }
            speech?.resume()
            narration?.resume()
        }
    }

    // MARK: Audio session events

    /// A phone call, Siri, or an alarm took over the audio: pause, and
    /// remember why so reading can resume afterward.
    private func interruptionBegan() {
        guard isSpeaking, !isPaused else { return }
        pause()
        pausedByInterruption = true
    }

    /// The interruption ended; resume if the system recommends it.
    private func interruptionEnded(shouldResume: Bool) {
        guard pausedByInterruption else { return }
        pausedByInterruption = false
        if shouldResume { resume() }
    }

    /// Pauses when headphones or another output disconnects, rather than
    /// continuing out loud on the speaker.
    private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
        else { return }
        pause()
    }

    public func stop() {
        session += 1
        pausedByInterruption = false
        synthesizer.stopSpeaking(at: .immediate)
        speech?.stop()
        speech = nil
        narration?.stop()
        narration = nil
        narrationAnchors = []
        units = []
        spokenString = nil
        isSpeaking = false
        isPaused = false
        text = nil
    }

    private func begin(_ content: RubyContent) {
        session += 1
        text = content.string
        units = RubyReadingUnits.units(in: content.string, words: content.words)
        isSpeaking = true
    }

    /// A completion handler for `session`, which should be the one `begin` is
    /// about to start. Built outside the main actor so audio threads can call it.
    private nonisolated static func finishHandler(for reader: RubyReader, session token: Int) -> @Sendable () -> Void {
        { [weak reader] in
            guard let reader else { return }
            Task { @MainActor in
                if reader.session == token { reader.stop() }
            }
        }
    }

    // MARK: Position

    /// The phrase at the current playback position, or `nil` before speech
    /// starts or between sentences.
    func spokenWord() -> SpokenWord? {
        guard let text else { return nil }
        let anchors: [RubyTimelineAnchor]
        let time: Double
        let duration: Double

        if let narration {
            anchors = narrationAnchors
            time = narration.currentTime
            duration = narration.duration
        } else if let speech, let state = speech.state(), let frame = state.currentFrame {
            anchors = speechAnchors(state)
            time = Double(frame) / state.sampleRate
            duration = Double(state.totalFrames) / state.sampleRate
        } else {
            return nil
        }

        guard let spoken = RubyReadingUnits.spokenUnit(
            at: time, anchors: anchors, units: units, text: text, duration: duration
        ) else { return nil }
        return SpokenWord(range: units[spoken.unit].range, progress: spoken.progress, elapsed: spoken.elapsed)
    }

    /// Anchors from the voice's word markers. Each unit starts at the
    /// earliest marker inside it, so a late marker on a particle (は after
    /// 吾輩) doesn't split the phrase. Markers reported together merge.
    private func speechAnchors(_ state: RubySpeechPlayback.State) -> [RubyTimelineAnchor] {
        var earliest: [Int: AVAudioFramePosition] = [:]
        for marker in state.markers {
            // Markers are offsets in what's spoken, which can differ from the text.
            let location = spokenString?.sourceOffset(marker.location) ?? marker.location
            guard let unit = RubyReadingUnits.unit(containing: location, in: units) else { continue }
            earliest[unit] = min(earliest[unit] ?? marker.frame, marker.frame)
        }

        var anchors: [RubyTimelineAnchor] = []
        for (unit, frame) in earliest.sorted(by: { $0.key < $1.key }) {
            let start = Double(frame) / state.sampleRate
            if let last = anchors.last, start < last.start + 0.08 { continue }
            anchors.append(RubyTimelineAnchor(unit: unit, start: start, end: nil))
        }
        // Some voices report no word timing at all; treat the whole text as
        // one stretch so emphasis still progresses through it.
        guard let first = anchors.first else { return [RubyTimelineAnchor(unit: 0, start: 0, end: nil)] }
        anchors[0] = RubyTimelineAnchor(unit: 0, start: first.start, end: nil)
        return anchors
    }
}

/// Plays synthesized speech buffers and records word markers as they're
/// produced. Synthesis callbacks arrive on a background thread, so state is
/// guarded by a lock.
nonisolated final class RubySpeechPlayback: @unchecked Sendable {
    struct State {
        /// Text location and audio frame of each word marker.
        let markers: [(location: Int, frame: AVAudioFramePosition)]
        /// Frames synthesized so far.
        let totalFrames: AVAudioFramePosition
        let sampleRate: Double
        /// Frame being played, or `nil` before playback starts.
        let currentFrame: AVAudioFramePosition?
    }

    var onFinish: (@Sendable () -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private struct Storage {
        var format: AVAudioFormat?
        var markerBytes: [(location: Int, byteOffset: Int)] = []
        var totalFrames: AVAudioFramePosition = 0
        var lastFrame: AVAudioFramePosition?
        var isPaused = false
        var isStopped = false
    }

    private let storage = Mutex(Storage())
    private var configurationObserver: (any NSObjectProtocol)?

    init() {
        engine.attach(player)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    func receive(buffer: AVAudioBuffer) {
        guard let buffer = buffer as? AVAudioPCMBuffer else { return }
        storage.withLock { storage in
            guard !storage.isStopped else { return }

            // An empty buffer marks the end of synthesis.
            guard buffer.frameLength > 0 else {
                scheduleEnd(format: storage.format)
                return
            }
            if storage.format == nil {
                // The audio session is already active; see `RubyAudioSession`.
                storage.format = buffer.format
                do {
                    try engine.connectNode(player, to: engine.mainMixerNode, format: buffer.format)
                    try engine.start()
                    try player.playAudio()
                } catch {
                    storage.isStopped = true
                    onFinish?()
                    return
                }
            }
            player.scheduleBuffer(buffer)
            storage.totalFrames += AVAudioFramePosition(buffer.frameLength)
        }
    }

    func receive(markers: [AVSpeechSynthesisMarker]) {
        storage.withLock { storage in
            for marker in markers where marker.mark == .word {
                storage.markerBytes.append((marker.textRange.location, marker.byteSampleOffset))
            }
        }
    }

    func state() -> State? {
        storage.withLock { storage in
            guard let format = storage.format, !storage.isStopped else { return nil }
            // Marker offsets are in bytes of the synthesized audio.
            let bytesPerFrame = max(Int(format.streamDescription.pointee.mBytesPerFrame), 1)
            // A paused player reports no render time, so keep the last
            // position. Right after resuming it can briefly report an earlier
            // one, so the position only ever moves forward.
            if !storage.isPaused, let nodeTime = player.lastRenderTime,
               let playerTime = player.playerTime(forNodeTime: nodeTime) {
                storage.lastFrame = max(storage.lastFrame ?? playerTime.sampleTime, playerTime.sampleTime)
            }
            return State(
                markers: storage.markerBytes.map { ($0.location, AVAudioFramePosition($0.byteOffset / bytesPerFrame)) },
                totalFrames: storage.totalFrames,
                sampleRate: format.sampleRate,
                currentFrame: storage.lastFrame
            )
        }
    }

    func pause() {
        storage.withLock { $0.isPaused = true }
        player.pause()
    }

    func resume() {
        storage.withLock { storage in
            storage.isPaused = false
            guard storage.format != nil, !storage.isStopped else { return }
            // An interruption stops the engine; start it again first.
            if !engine.isRunning { try? engine.start() }
            try? player.playAudio()
        }
    }

    /// The engine stops when the output changes, such as when headphones
    /// connect. Start it again so speech doesn't go silent.
    private func restartAfterConfigurationChange() {
        storage.withLock { storage in
            guard storage.format != nil, !storage.isStopped, !storage.isPaused else { return }
            try? engine.start()
            try? player.playAudio()
        }
    }

    func stop() {
        storage.withLock { $0.isStopped = true }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        player.stop()
        engine.stop()
    }

    /// Schedules a one-frame silent buffer whose completion marks the end of
    /// playback. Called with the mutex held.
    private func scheduleEnd(format: AVAudioFormat?) {
        guard let format, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else {
            onFinish?()
            return
        }
        silence.frameLength = 1
        let onFinish = onFinish
        player.scheduleBuffer(silence, completionCallbackType: .dataPlayedBack) { _ in
            onFinish?()
        }
    }
}
