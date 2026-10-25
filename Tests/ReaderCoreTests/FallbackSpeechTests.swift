import XCTest
@testable import ReaderCore

final class FallbackSpeechTests: XCTestCase {
    func testPrepareFailureReleasesPreferredBeforeCPUAndDoesNotRetry() throws {
        let trace = Trace()
        let primary = ProbeRuntime("coreml", trace: trace); primary.prepareError = SpeechError.resource("missing frontend")
        let cpu = ProbeRuntime("cpu", trace: trace)
        let runtime = FallbackSpeechRuntime(preferred: primary, fallback: cpu)
        try runtime.prepare(); try runtime.prepare()
        XCTAssertEqual(trace.events, ["coreml.prepare", "coreml.release", "cpu.prepare"])
        XCTAssertEqual(runtime.cacheIdentity, "cpu")
        XCTAssertEqual(runtime.diagnostics.selectedBackend, "CPU")
        XCTAssertTrue(runtime.diagnostics.fallbackReason?.contains("missing frontend") == true)
    }

    func testPredictionFailureReleasesPreferredBeforeCPUSynthesis() throws {
        let trace = Trace()
        let primary = ProbeRuntime("coreml", trace: trace); primary.synthesisError = SpeechError.invalidAudio
        let runtime = FallbackSpeechRuntime(preferred: primary, fallback: ProbeRuntime("cpu", trace: trace))
        _ = try runtime.synthesize(request())
        XCTAssertEqual(trace.events, ["coreml.prepare", "coreml.synthesize", "coreml.release", "cpu.prepare", "cpu.synthesize"])
        XCTAssertEqual(runtime.cacheIdentity, "cpu")
        runtime.releaseResources()
        try runtime.prepare()
        XCTAssertEqual(trace.events.filter { $0 == "coreml.prepare" }.count, 1)
    }

    func testCancellationDoesNotTriggerCPUFallback() throws {
        let trace = Trace(); let primary = ProbeRuntime("coreml", trace: trace)
        primary.synthesisError = CancellationError()
        let runtime = FallbackSpeechRuntime(preferred: primary, fallback: ProbeRuntime("cpu", trace: trace))
        XCTAssertThrowsError(try runtime.synthesize(request())) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(trace.events.contains { $0.hasPrefix("cpu.") })
        XCTAssertNil(runtime.diagnostics.fallbackReason)
    }

    func testFailedCPUPreparationMustBeRetriedBeforeSynthesis() throws {
        let trace = Trace()
        let primary = ProbeRuntime("coreml", trace: trace); primary.prepareError = SpeechError.resource("missing frontend")
        let cpu = ProbeRuntime("cpu", trace: trace); cpu.prepareError = SpeechError.resource("temporarily unavailable")
        let runtime = FallbackSpeechRuntime(preferred: primary, fallback: cpu)
        XCTAssertThrowsError(try runtime.prepare())
        cpu.prepareError = nil
        _ = try runtime.synthesize(request())
        XCTAssertEqual(trace.events.filter { $0 == "cpu.prepare" }.count, 2)
        XCTAssertEqual(trace.events.filter { $0 == "coreml.prepare" }.count, 1)
        XCTAssertEqual(trace.events, ["coreml.prepare", "coreml.release", "cpu.prepare", "cpu.release", "cpu.prepare", "cpu.synthesize"])
    }

    func testRepreparedPreferredRuntimeIsReleasedBeforeLaterFallback() throws {
        let trace = Trace(); let primary = ProbeRuntime("coreml", trace: trace)
        let runtime = FallbackSpeechRuntime(preferred: primary, fallback: ProbeRuntime("cpu", trace: trace))
        try runtime.prepare()
        runtime.releaseResources()
        primary.prepareError = SpeechError.resource("failed after recreation")
        try runtime.prepare()
        XCTAssertEqual(trace.events, ["coreml.prepare", "coreml.release", "coreml.prepare", "coreml.release", "cpu.prepare"])
    }

    func testServiceCachesByIdentityAfterPrepareAndAfterPredictionFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FallbackCache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let trace = Trace(); let primary = ProbeRuntime("coreml", trace: trace)
        primary.synthesisError = SpeechError.invalidAudio
        let runtime = FallbackSpeechRuntime(preferred: primary, fallback: ProbeRuntime("cpu", trace: trace))
        let service = LocalSpeechService(runtime: runtime, cacheDirectory: root)
        let first = try await service.synthesize(text: "こんにちは", language: "ja-JP", rate: 1)
        let cached = try await service.synthesize(text: "こんにちは", language: "ja-JP", rate: 1)
        XCTAssertEqual(first, cached)
        XCTAssertEqual(trace.events.filter { $0 == "cpu.synthesize" }.count, 1)
        let sameCPU = LocalSpeechService(runtime: ProbeRuntime("cpu", trace: Trace()), cacheDirectory: root)
        let cpuURL = try await sameCPU.synthesize(text: "こんにちは", language: "ja-JP", rate: 1)
        XCTAssertEqual(first, cpuURL, "Fallback PCM must use the actual CPU cache identity")
        let counts = try FileManager.default.contentsOfDirectory(atPath: root.path).count
        XCTAssertEqual(counts, 1)
    }

    func testPrepareTimeIdentityChangeAlsoUsesEffectiveCacheKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreparedCache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ProbeRuntime("unprepared", trace: Trace()); runtime.identityAfterPrepare = "ready"
        let service = LocalSpeechService(runtime: runtime, cacheDirectory: root)
        let first = try await service.synthesize(text: "こんにちは", language: "ja-JP", rate: 1)
        let second = try await service.synthesize(text: "こんにちは", language: "ja-JP", rate: 1)
        XCTAssertEqual(first, second)
    }

    private func request() throws -> SpeechRequest { try SpeechRequest(text: "こんにちは", language: "ja-JP", voice: .metan, rate: 1) }
}

private final class Trace: @unchecked Sendable { var events = [String]() }
private final class ProbeRuntime: SpeechRuntime, @unchecked Sendable {
    var cacheIdentity: String
    let label: String
    let trace: Trace
    var prepareError: Error?
    var synthesisError: Error?
    var identityAfterPrepare: String?
    init(_ identity: String, trace: Trace) { cacheIdentity = identity; label = identity; self.trace = trace }
    func prepare() throws { trace.events.append(label + ".prepare"); if let prepareError { throw prepareError }; if let identityAfterPrepare { cacheIdentity = identityAfterPrepare } }
    func synthesize(_ request: SpeechRequest) throws -> Data { trace.events.append(label + ".synthesize"); if let synthesisError { throw synthesisError }; return try TalkPCM.wav(samples: Array(repeating: 0.5, count: 256)) }
    func releaseResources() { trace.events.append(label + ".release") }
}
