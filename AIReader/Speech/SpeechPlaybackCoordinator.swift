import AVFoundation
import MediaPlayer
import Observation
import ReaderCore
import UIKit

/// One app-owned session. Native inference stays on LocalSpeechService's serial queue.
@MainActor @Observable
final class SpeechPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {
    enum State: Equatable { case idle, preparing, playing, paused, completed, failed }
    private(set) var state: State = .idle
    private(set) var documentID: UUID?
    private(set) var title = ""
    private(set) var paragraphIndex = 0
    private(set) var segmentIndex = 0
    private(set) var segmentCount = 0
    private(set) var errorMessage: String?
    private(set) var voice: SpeechVoice = .metan
    private(set) var rate = 1.0
    private(set) var highlightedSegmentIndex: Int?
    var onParagraph: ((UUID, Int) -> Void)?
    let service: LocalSpeechService
    var isActive: Bool { state == .playing || state == .preparing }
    var hasSession: Bool { state != .idle }
    var canChangeVoice: Bool { !isActive }
    var highlightedSentence: SpeechSegment? {
        guard let index = highlightedSegmentIndex, segments.indices.contains(index) else { return nil }
        return segments[index]
    }
    var status: String {
        switch state {
        case .idle: return "日语 · 离线朗读"
        case .preparing: return "正在准备语音…"
        case .playing: return "正在朗读 · 第 \(segmentIndex + 1) / \(segmentCount) 句"
        case .paused: return "已暂停 · 第 \(segmentIndex + 1) / \(segmentCount) 句"
        case .completed: return "朗读完成"
        case .failed: return errorMessage ?? "朗读失败，请重试"
        }
    }

    @ObservationIgnored private let audioSession = SpeechAudioSession()
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var document: ReaderDocument?
    @ObservationIgnored private var segments: [SpeechSegment] = []
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var prefetch: Task<URL, Error>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var completion: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var wantsPlayback = true
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var observations: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init(service: LocalSpeechService) {
        self.service = service
        super.init()
        installSystemControls()
    }

    static func makeDefault() -> SpeechPlaybackCoordinator {
        let resources = Bundle.main.bundleURL.appendingPathComponent("Voicevox", isDirectory: true)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Speech-v1", isDirectory: true)
        return SpeechPlaybackCoordinator(service: LocalSpeechService(runtime: VoicevoxNativeRuntime(resourceDirectory: resources), cacheDirectory: cache))
    }

    func toggle(document: ReaderDocument, paragraph: Int, voice: SpeechVoice, rate: Double) {
        if documentID == document.id && self.document?.contentRevision == document.contentRevision {
            if isActive { pause(); return }
            if state == .paused { resume(); return }
        }
        start(document: document, paragraph: paragraph, voice: voice, rate: rate)
    }

    func start(document: ReaderDocument, paragraph: Int, voice: SpeechVoice, rate: Double) {
        stop()
        self.document = document; documentID = document.id; title = document.title
        self.voice = voice; self.rate = rate
        guard document.language == "ja-JP" else { fail(SpeechError.unsupportedLanguage); return }
        segments = JapaneseSpeechSegmenter.segments(paragraphs: document.paragraphs)
        segmentCount = segments.count
        guard !segments.isEmpty else { fail(SpeechError.invalidText); return }
        let index = segments.firstIndex { $0.paragraphIndex >= paragraph } ?? 0
        run(from: index)
    }

    func preview(_ voice: SpeechVoice, rate: Double) {
        let sample = ReaderDocument(title: "音色试听", text: "こんにちは。今日は日本語の本を読みましょう。", language: "ja-JP")
        start(document: sample, paragraph: 0, voice: voice, rate: rate)
        // Previews use this same service and player, but never write library progress.
        documentID = nil
    }

    func pause() {
        guard isActive else { return }
        wantsPlayback = false; player?.pause(); state = .paused
        prefetch?.cancel(); prefetch = nil
        updateNowPlaying()
        endBackgroundTask()
    }

    func resume() {
        if (state == .completed || state == .failed) && !segments.isEmpty {
            let index = state == .completed ? 0 : segmentIndex
            cancelPipeline(); run(from: index); return
        }
        guard state == .paused else { return }
        wantsPlayback = true
        state = .preparing
        let token = session
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.audioSession.activate()
                guard self.session == token, self.wantsPlayback, !Task.isCancelled else { return }
                if let player = self.player {
                    guard player.play() else { self.fail(SpeechError.invalidAudio); return }
                    self.highlightedSegmentIndex = self.segmentIndex
                    self.state = .playing
                } else { self.beginBackgroundTask() }
                self.updateNowPlaying()
            } catch {
                guard self.session == token else { return }
                self.fail(error)
            }
        }
    }

    func skip(_ offset: Int) {
        guard !segments.isEmpty else { return }
        let next = min(max(segmentIndex + offset, 0), segments.count - 1)
        cancelPipeline()
        run(from: next)
    }

    func stop() {
        cancelPipeline()
        state = .idle; documentID = nil; document = nil; title = ""
        segments = []; segmentCount = 0; errorMessage = nil; highlightedSegmentIndex = nil
        service.releaseResources()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        audioSession.deactivate()
    }

    /// Repository snapshots are the authority for revision, deletion, voice and rate changes.
    func reconcile(documents: [ReaderDocument], preferences: ReaderPreferences) {
        guard let id = documentID, let old = document else { return }
        guard let current = documents.first(where: { $0.id == id && $0.deletedAt == nil }), current.contentRevision == old.contentRevision else { stop(); return }
        let newRate = current.playbackRate ?? preferences.defaultRate
        if voice != preferences.voice || abs(rate - newRate) > 0.001 {
            if state == .completed || state == .failed {
                document = current; voice = preferences.voice; rate = newRate; return
            }
            let wasActive = isActive
            let index = segmentIndex
            cancelPipeline(); document = current; voice = preferences.voice; rate = newRate
            run(from: index, autoplay: wasActive)
        }
    }

    func clearAudioCache() async throws {
        stop()
        try await service.clearCache()
        service.releaseResources()
    }

    private func run(from index: Int, autoplay: Bool = true) {
        let token = session
        wantsPlayback = autoplay; errorMessage = nil; segmentIndex = index
        state = autoplay ? .preparing : .paused
        let currentVoice = voice, currentRate = rate
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if autoplay { try await self.audioSession.activate() }
                try Task.checkCancellation()
                guard self.session == token else { return }
                for position in index..<self.segments.count {
                    try Task.checkCancellation()
                    guard self.session == token else { return }
                    self.segmentIndex = position
                    let segment = self.segments[position]
                    let enteredParagraph = position == index || self.paragraphIndex != segment.paragraphIndex
                    self.paragraphIndex = segment.paragraphIndex
                    if enteredParagraph, let id = self.documentID { self.onParagraph?(id, segment.paragraphIndex) }
                    if self.wantsPlayback { self.state = .preparing; self.beginBackgroundTask() }
                    let url: URL
                    if let pending = self.prefetch {
                        self.prefetch = nil
                        url = try await pending.value
                    } else {
                        url = try await self.service.synthesize(text: segment.text, language: "ja-JP", voice: currentVoice, rate: currentRate)
                    }
                    try Task.checkCancellation()
                    guard self.session == token else { return }
                    if position + 1 < self.segments.count && self.wantsPlayback {
                        let next = self.segments[position + 1].text
                        self.prefetch = Task { try await self.service.synthesize(text: next, language: "ja-JP", voice: currentVoice, rate: currentRate) }
                    }
                    try await self.play(url, session: token, position: position)
                    guard self.session == token else { return }
                    self.player = nil
                }
                self.state = .completed
                self.highlightedSegmentIndex = nil
                self.player = nil; self.endBackgroundTask(); self.updateNowPlaying()
                self.audioSession.deactivate()
                self.service.releaseResources()
            } catch {
                guard self.session == token else { return }
                if error is CancellationError { self.stop() }
                else { self.fail(error) }
            }
        }
    }

    private func play(_ url: URL, session token: UUID, position: Int) async throws {
        let prepared = try await audioSession.preparePlayer(url)
        try Task.checkCancellation()
        guard session == token else { throw CancellationError() }
        let audio = prepared.player
        audio.delegate = self
        player = audio
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            if wantsPlayback {
                if audio.play() {
                    highlightedSegmentIndex = position
                    state = .playing
                }
                else { finishAudio(.failure(SpeechError.invalidAudio)) }
            } else { state = .paused }
            endBackgroundTask(); updateNowPlaying()
        }
    }

    private func cancelPipeline() {
        session = UUID()
        activationTask?.cancel(); activationTask = nil
        task?.cancel(); task = nil
        prefetch?.cancel(); prefetch = nil
        service.invalidate()
        player?.stop(); player?.delegate = nil; player = nil
        finishAudio(.failure(CancellationError()))
        endBackgroundTask()
    }

    private func finishAudio(_ result: Result<Void, Error>) {
        let pending = completion; completion = nil
        pending?.resume(with: result)
    }

    private func fail(_ error: Error) {
        cancelPipeline(); state = .failed; errorMessage = error.localizedDescription; highlightedSegmentIndex = nil
        updateNowPlaying()
        audioSession.deactivate()
        service.releaseResources()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        finishAudio(flag ? .success(()) : .failure(SpeechError.invalidAudio))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        finishAudio(.failure(error ?? SpeechError.invalidAudio))
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare reading audio") { [weak self] in
            Task { @MainActor in self?.stop() }
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }

    private func updateNowPlaying() {
        guard hasSession else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: voice.credit,
            MPMediaItemPropertyAlbumTitle: "第 \(segmentIndex + 1) / \(segmentCount) 句",
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
    }

    private func installSystemControls() {
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
            let target = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            remoteTargets.append((command, target)); command.isEnabled = true
        }
        bind(center.playCommand) { [weak self] in self?.resume() }
        bind(center.pauseCommand) { [weak self] in self?.pause() }
        bind(center.togglePlayPauseCommand) { [weak self] in
            guard let self else { return }; self.isActive ? self.pause() : self.resume()
        }
        bind(center.nextTrackCommand) { [weak self] in self?.skip(1) }
        bind(center.previousTrackCommand) { [weak self] in self?.skip(-1) }
        bind(center.stopCommand) { [weak self] in self?.stop() }
        let notifications = NotificationCenter.default
        observations.append(notifications.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        })
        observations.append(notifications.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.pause() }
        })
        observations.append(notifications.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
        observations.append(notifications.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.prefetch?.cancel(); self.prefetch = nil
                self.service.releaseResources()
            }
        })
    }

    deinit {
        for observer in observations { NotificationCenter.default.removeObserver(observer) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
    }
}

/// Audio session IPC can block; keep category/activation changes off the UI thread.
private final class SpeechAudioSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.aireader.audio-session", qos: .userInitiated)
    func activate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    if session.category != .playback || session.mode != .spokenAudio {
                        try session.setCategory(.playback, mode: .spokenAudio)
                    }
                    try session.setActive(true)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    struct PreparedAudio: @unchecked Sendable { let player: AVAudioPlayer }
    func preparePlayer(_ url: URL) async throws -> PreparedAudio {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let audio = try AVAudioPlayer(contentsOf: url)
                    guard audio.prepareToPlay() else { throw SpeechError.invalidAudio }
                    continuation.resume(returning: PreparedAudio(player: audio))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func deactivate() {
        queue.async { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
