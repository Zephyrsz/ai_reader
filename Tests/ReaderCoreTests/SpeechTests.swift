import XCTest
@testable import ReaderCore

final class SpeechTests: XCTestCase {
    func testRepeatedTerminalPunctuationStillRespectsSegmentLimit() {
        let text = "日本語" + String(repeating: "。", count: 250) + "続きます。"
        let segments = JapaneseSpeechSegmenter.segments(paragraphs: [text], maximumCharacters: 60)
        XCTAssertTrue(segments.allSatisfy { $0.text.count <= 60 })
        XCTAssertEqual(segments.map(\.text).joined(), text)
    }

    func testJapaneseSentencesKeepClosingQuotesAndParagraphMapping() {
        let segments = JapaneseSpeechSegmenter.segments(paragraphs: ["「こんにちは。」今日は晴れです！", "価格は3.14です。次へ。"])
        XCTAssertEqual(segments.map(\.text), ["「こんにちは。」", "今日は晴れです！", "価格は3.14です。", "次へ。"])
        XCTAssertEqual(segments.map(\.paragraphIndex), [0, 0, 1, 1])
    }

    func testUnpunctuatedTextIsBoundedWithoutLosingCharacters() {
        let text = String(repeating: "あ", count: 137)
        let segments = JapaneseSpeechSegmenter.segments(paragraphs: [text], maximumCharacters: 50)
        XCTAssertEqual(segments.map(\.text).joined(), text)
        XCTAssertEqual(segments.map { $0.text.count }, [50, 50, 37])
    }

    func testOldPreferencesDecodeAndNewVoicePersists() throws {
        let old = Data(#"{"appearance":"dark","fontSize":22,"lineSpacing":8,"defaultRate":1.25,"followSpeech":true}"#.utf8)
        var prefs = try JSONDecoder().decode(ReaderPreferences.self, from: old)
        XCTAssertEqual(prefs.voice, .metan)
        XCTAssertEqual(prefs.fontSize, 22)
        prefs.voice = .whiteCUL
        let reopened = try JSONDecoder().decode(ReaderPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(reopened.voice, .whiteCUL)
    }

    func testInvalidRequestsDoNotReachNativeRuntime() throws {
        for (text, language, rate) in [(" ", "ja-JP", 1.0), ("a\0b", "ja-JP", 1), ("hello", "en-US", 1), ("こんにちは", "ja-JP", Double.nan), ("こんにちは", "ja-JP", 0.1)] {
            XCTAssertThrowsError(try SpeechRequest(text: text, language: language, voice: .metan, rate: rate))
        }
    }

    func testCacheSeparatesVoiceRateAndRuntimeAndRegeneratesCorruption() async throws {
        let root = temporaryRoot()
        let service = LocalSpeechService(runtime: FixtureSpeechRuntime(identity: "model-a"), cacheDirectory: root)
        let first = try await service.synthesize(text: "こんにちは", language: "ja-JP", voice: .metan, rate: 1)
        let repeatURL = try await service.synthesize(text: "こんにちは", language: "ja-JP", voice: .metan, rate: 1)
        XCTAssertEqual(first, repeatURL)
        let otherVoice = try await service.synthesize(text: "こんにちは", language: "ja-JP", voice: .tsumugi, rate: 1)
        let otherRate = try await service.synthesize(text: "こんにちは", language: "ja-JP", voice: .metan, rate: 1.5)
        XCTAssertNotEqual(first, otherVoice)
        XCTAssertNotEqual(first, otherRate)
        let upgraded = LocalSpeechService(runtime: FixtureSpeechRuntime(identity: "model-b"), cacheDirectory: root)
        let otherModel = try await upgraded.synthesize(text: "こんにちは", language: "ja-JP", voice: .metan, rate: 1)
        XCTAssertNotEqual(first, otherModel)
        try Data("broken".utf8).write(to: first)
        let repaired = try await service.synthesize(text: "こんにちは", language: "ja-JP", voice: .metan, rate: 1)
        XCTAssertEqual(try SpeechWAV(data: Data(contentsOf: repaired)).sampleRate, 24_000)
    }

    func testCacheBudgetEvictsOlderAudio() async throws {
        let root = temporaryRoot()
        let service = LocalSpeechService(runtime: FixtureSpeechRuntime(identity: "budget"), cacheDirectory: root, cacheBudget: 4_000)
        let first = try await service.synthesize(text: "一", language: "ja-JP", rate: 1)
        let second = try await service.synthesize(text: "二", language: "ja-JP", rate: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testCancelDiscardsInFlightOutputAndAllowsANewSession() async throws {
        let root = temporaryRoot()
        let entered = expectation(description: "entered native call")
        let release = DispatchSemaphore(value: 0)
        let runtime = FixtureSpeechRuntime(identity: "cancel") { entered.fulfill(); release.wait() }
        let service = LocalSpeechService(runtime: runtime, cacheDirectory: root)
        let old = Task { try await service.synthesize(text: "古い文章", language: "ja-JP", rate: 1) }
        await fulfillment(of: [entered], timeout: 3)
        await service.cancel()
        release.signal()
        do { _ = try await old.value; XCTFail("Late audio must be discarded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix("wav") }.count) ?? 0, 0)
        let next = try await service.synthesize(text: "新しい文章", language: "ja-JP", rate: 1)
        XCTAssertGreaterThan(try SpeechWAV(data: Data(contentsOf: next)).duration, 0)
    }

    func testQueuedCancelledRequestNeverProducesAudio() async throws {
        let entered = expectation(description: "first running")
        let release = DispatchSemaphore(value: 0)
        let service = LocalSpeechService(runtime: FixtureSpeechRuntime(identity: "queued") { entered.fulfill(); release.wait() }, cacheDirectory: temporaryRoot())
        let first = Task { try await service.synthesize(text: "最初", language: "ja-JP", rate: 1) }
        await fulfillment(of: [entered], timeout: 3)
        let queued = Task { try await service.synthesize(text: "待機", language: "ja-JP", rate: 1) }
        queued.cancel()
        release.signal()
        _ = try await first.value
        do { _ = try await queued.value; XCTFail("Cancelled queued work must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpeechTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

// The native model call is slow/external; the service, cache, cancellation and WAV parser remain real.
private final class FixtureSpeechRuntime: SpeechRuntime, @unchecked Sendable {
    let cacheIdentity: String
    private var firstCall: (() -> Void)?
    init(identity: String, firstCall: (() -> Void)? = nil) { cacheIdentity = identity; self.firstCall = firstCall }
    func prepare() throws {}
    func releaseResources() {}
    func synthesize(_ request: SpeechRequest) throws -> Data {
        let first = firstCall; firstCall = nil; first?()
        var data = Data("RIFF".utf8)
        func u16(_ x: UInt16) { var v = x.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ x: UInt32) { var v = x.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        u32(3_236); data.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(24_000); u32(48_000); u16(2); u16(16); data.append(Data("data".utf8)); u32(3_200)
        data.append(Data(repeating: 1, count: 3_200))
        return data
    }
}
