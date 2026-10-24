import XCTest
import CryptoKit
import ReaderCore
@testable import AIReader

final class NativeSpeechTests: XCTestCase {
    func testFourExistingVoicesProduceDistinctNonSilentAudioAndSwitchBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeVoices-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = VoicevoxNativeRuntime(resourceDirectory: try XCTUnwrap(Bundle.main.url(forResource: "Voicevox", withExtension: nil)))
        let service = LocalSpeechService(runtime: runtime, cacheDirectory: root)
        var hashes = Set<String>()
        var measurements: [[String: Any]] = []
        for voice in SpeechVoice.allCases {
            let begin = Date()
            let url = try await service.synthesize(text: "こんにちは。今日は本を読みます。", language: "ja-JP", voice: voice, rate: 1)
            let elapsed = Date().timeIntervalSince(begin)
            let data = try Data(contentsOf: url)
            let wav = try SpeechWAV(data: data)
            XCTAssertEqual(wav.sampleRate, 24_000)
            XCTAssertGreaterThan(wav.duration, 0.5)
            XCTAssertGreaterThan(wav.peak, 100)
            hashes.insert(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            measurements.append(["style": voice.rawValue, "voice": voice.name, "duration_s": wav.duration, "wall_s": elapsed, "rtf": elapsed / wav.duration, "backend": "CPU"])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.microsoft.waveform-audio")
            attachment.name = "style-\(voice.rawValue).wav"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(hashes.count, 4, "The actual style ID must reach the native model")
        // A different text misses cache and forces 8.vvm -> 0.vvm, exercising unload/reload.
        let back = try await service.synthesize(text: "もう一度読みましょう。", language: "ja-JP", voice: .metan, rate: 1)
        XCTAssertGreaterThan(try SpeechWAV(data: Data(contentsOf: back)).peak, 100)
        let report = XCTAttachment(data: try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        report.name = "four-voices-cpu-measurements.json"; report.lifetime = .keepAlways; add(report)
        service.releaseResources()
    }

    func testModelSpeedAffectsActualWaveDuration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeRate-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = LocalSpeechService(runtime: VoicevoxNativeRuntime(resourceDirectory: try XCTUnwrap(Bundle.main.url(forResource: "Voicevox", withExtension: nil))), cacheDirectory: root)
        let normal = try await service.synthesize(text: "日本語の本を読みます。", language: "ja-JP", voice: .tsumugi, rate: 1)
        let fast = try await service.synthesize(text: "日本語の本を読みます。", language: "ja-JP", voice: .tsumugi, rate: 1.5)
        let normalWAV = try SpeechWAV(data: Data(contentsOf: normal))
        let fastWAV = try SpeechWAV(data: Data(contentsOf: fast))
        XCTAssertLessThan(fastWAV.duration, normalWAV.duration * 0.85)
        XCTAssertGreaterThan(fastWAV.peak, 100)
        service.releaseResources()
    }

    func testCorruptResourcesFailBeforeNativeInitialization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorruptResources-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dictionary"), withIntermediateDirectories: true)
        try Data("tampered".utf8).write(to: root.appendingPathComponent("dictionary/sys.dic"))
        let manifest: [String: Any] = ["identity": "corrupt", "coreVersion": "0.17.0", "ortVersion": "1.23.2", "backend": "CPU", "files": ["dictionary/sys.dic": ["sha256": "invalid", "bytes": 8]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))
        let service = LocalSpeechService(runtime: VoicevoxNativeRuntime(resourceDirectory: root), cacheDirectory: root.appendingPathComponent("cache"))
        do { try await service.prepare(language: "ja-JP"); XCTFail("Corrupt resources must fail") }
        catch let error as SpeechError { if case .resource = error {} else { XCTFail("Expected resource error") } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache").path))
    }

    func testMissingResourcesFailWithoutCreatingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = LocalSpeechService(runtime: VoicevoxNativeRuntime(resourceDirectory: root), cacheDirectory: root)
        do { _ = try await service.synthesize(text: "こんにちは", language: "ja-JP", rate: 1); XCTFail("Missing assets must fail") }
        catch { XCTAssertTrue(error is SpeechError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
