import XCTest
@testable import ReaderCore

final class TTSEngineTests: XCTestCase {
    func testDeferredEngineAdvertisesNoLanguagesAndNeverCreatesAudio() async throws {
        let engine = UnavailableTTSEngine()
        XCTAssertTrue(engine.supportedLanguages.isEmpty)
        do {
            try await engine.prepare(language: "ja-JP")
            XCTFail("A deferred engine must report that TTS is unavailable.")
        } catch { XCTAssertEqual(error as? RepositoryError, .unavailable) }
        do {
            _ = try await engine.synthesize(text: "こんにちは", language: "ja-JP", rate: 1)
            XCTFail("The deferred engine must never synthesize placeholder audio.")
        } catch { XCTAssertEqual(error as? RepositoryError, .unavailable) }
    }
}
