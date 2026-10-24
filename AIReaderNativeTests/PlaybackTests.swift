import XCTest
import ReaderCore
@testable import AIReader

@MainActor
final class PlaybackTests: XCTestCase {
    func testPauseWhilePreparingKeepsLateAudioPausedThenResumes() async throws {
        let (coordinator, runtime, root) = makeCoordinator()
        defer { coordinator.stop(); runtime.proceed.signal(); try? FileManager.default.removeItem(at: root) }
        coordinator.start(document: ReaderDocument(title: "Test", text: "日本語を読みます。"), paragraph: 0, voice: .metan, rate: 1)
        try await waitUntil { runtime.started }
        coordinator.pause()
        runtime.proceed.signal()
        try await waitUntil { runtime.finished }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(coordinator.state, .paused)
        coordinator.resume()
        try await waitUntil { coordinator.state == .playing }
        coordinator.stop()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testRevisionAndDeletionDiscardInFlightAudio() async throws {
        for delete in [false, true] {
            let (coordinator, runtime, root) = makeCoordinator()
            defer { coordinator.stop(); runtime.proceed.signal(); try? FileManager.default.removeItem(at: root) }
            var document = ReaderDocument(title: "Test", text: "日本語を読みます。")
            coordinator.start(document: document, paragraph: 0, voice: .tsumugi, rate: 1)
            try await waitUntil { runtime.started }
            document.contentRevision += 1
            coordinator.reconcile(documents: delete ? [] : [document], preferences: ReaderPreferences())
            runtime.proceed.signal()
            try await waitUntil { runtime.finished }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(coordinator.state, .idle)
            XCTAssertNil(coordinator.documentID)
        }
    }

    func testChangingVoiceAndRateReplacesRequestWithoutAutoplayWhenPaused() async throws {
        let (coordinator, runtime, root) = makeCoordinator()
        defer { coordinator.stop(); runtime.proceed.signal(); try? FileManager.default.removeItem(at: root) }
        let document = ReaderDocument(title: "Test", text: "日本語を読みます。")
        coordinator.start(document: document, paragraph: 0, voice: .metan, rate: 1)
        try await waitUntil { runtime.started }
        coordinator.pause()
        var preferences = ReaderPreferences(); preferences.voice = .whiteCUL; preferences.defaultRate = 1.5
        coordinator.reconcile(documents: [document], preferences: preferences)
        runtime.proceed.signal()
        try await waitUntil { runtime.requests.count >= 2 }
        XCTAssertEqual(runtime.requests.last?.voice, .whiteCUL)
        XCTAssertEqual(runtime.requests.last?.rate, 1.5)
        XCTAssertEqual(coordinator.state, .paused)
    }

    func testParagraphProgressIsSavedOnceAcrossSentences() async throws {
        let (coordinator, runtime, root) = makeCoordinator()
        defer { coordinator.stop(); runtime.proceed.signal(); try? FileManager.default.removeItem(at: root) }
        var reported: [Int] = []
        coordinator.onParagraph = { _, paragraph in reported.append(paragraph) }
        coordinator.start(document: ReaderDocument(title: "Test", text: "最初の文。次の文。\n次の段落。"), paragraph: 0, voice: .metan, rate: 1)
        runtime.proceed.signal()
        try await waitUntil { coordinator.segmentIndex == 1 }
        XCTAssertEqual(reported, [0], "Do not rewrite the entire document for each sentence in one paragraph")
        coordinator.skip(1)
        try await waitUntil { coordinator.paragraphIndex == 1 }
        XCTAssertEqual(reported, [0, 1])
    }

    func testUnsupportedLanguageDoesNotEnterNativeRuntime() async throws {
        let (coordinator, runtime, root) = makeCoordinator()
        defer { coordinator.stop(); try? FileManager.default.removeItem(at: root) }
        coordinator.start(document: ReaderDocument(title: "Test", text: "Hello", language: "en-US"), paragraph: 0, voice: .metan, rate: 1)
        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertFalse(runtime.started)
    }

    private func makeCoordinator() -> (SpeechPlaybackCoordinator, ControlledRuntime, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Playback-\(UUID())")
        let runtime = ControlledRuntime()
        return (SpeechPlaybackCoordinator(service: LocalSpeechService(runtime: runtime, cacheDirectory: root)), runtime, root)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Timed out waiting for playback state")
    }
}

private final class ControlledRuntime: SpeechRuntime, @unchecked Sendable {
    let cacheIdentity = "playback-fixture"
    let proceed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didStart = false, didFinish = false
    private var recorded: [SpeechRequest] = []
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return didFinish }
    var requests: [SpeechRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func prepare() throws {}
    func releaseResources() {}
    func synthesize(_ request: SpeechRequest) throws -> Data {
        lock.lock(); recorded.append(request); let first = !didStart; didStart = true; lock.unlock()
        if first { _ = proceed.wait(timeout: .now() + 10) }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        let count = 48_000
        text("RIFF"); number(UInt32(36 + count * 2)); text("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(24_000)); number(UInt32(48_000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(count * 2))
        for index in 0..<count { number(Int16(sin(Double(index) * 2 * .pi * 440 / 24_000) * 1_000)) }
        lock.lock(); didFinish = true; lock.unlock()
        return data
    }
}
