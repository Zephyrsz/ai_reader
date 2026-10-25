import XCTest
@testable import ReaderCore

final class TalkDecoderTests: XCTestCase {
    func testPaddingUsesSilenceAndCroppingRemovesBothMarginsAndBucketTail() throws {
        let frames = try TalkFrameFeatures(f0: [100, 120], phoneme: Array(repeating: 0.25, count: 90), speakerID: 3)
        let plan = try TalkFramePlan(features: frames, bucketFrames: 80)
        XCTAssertEqual(plan.f0.count, 80)
        XCTAssertEqual(Array(plan.f0[38..<40]), [100, 120])
        XCTAssertEqual(plan.f0[0], 0)
        for index in [0, 37, 40, 79] {
            XCTAssertEqual(plan.phoneme[index * 45], 1)
            XCTAssertEqual(plan.phoneme[index * 45 + 1], 0)
        }
        XCTAssertEqual(plan.phoneme[38 * 45], 0.25)
        let wave = (0..<(80 * 256)).map(Float.init)
        XCTAssertEqual(try plan.crop(wave), Array(wave[(38 * 256)..<(40 * 256)]))
        XCTAssertThrowsError(try plan.crop(Array(wave.dropLast())))
    }

    func testRejectsMalformedFeaturesAndUnboundedOrUndersizedBuckets() throws {
        XCTAssertThrowsError(try TalkFrameFeatures(f0: [], phoneme: [], speakerID: 0))
        XCTAssertThrowsError(try TalkFrameFeatures(f0: [1], phoneme: [1], speakerID: 0))
        XCTAssertThrowsError(try TalkFrameFeatures(f0: [.nan], phoneme: Array(repeating: 0, count: 45), speakerID: 0))
        XCTAssertThrowsError(try TalkFrameFeatures(f0: [0], phoneme: Array(repeating: .infinity, count: 45), speakerID: 0))
        XCTAssertThrowsError(try TalkFrameFeatures(f0: [0], phoneme: Array(repeating: 0, count: 45), speakerID: -1))
        XCTAssertThrowsError(try TalkFrameFeatures(f0: [0], phoneme: Array(repeating: 0, count: 45), speakerID: Int64.max))
        let feature = try TalkFrameFeatures(f0: [0], phoneme: Array(repeating: 0, count: 45), speakerID: 0)
        for bucket in [76, Int.max, 8_193] { XCTAssertThrowsError(try TalkFramePlan(features: feature, bucketFrames: bucket)) }
    }

    func testRejectsNonFiniteWaveAndProduces24kMonoPCM() throws {
        let feature = try TalkFrameFeatures(f0: [0], phoneme: Array(repeating: 0, count: 45), speakerID: 0)
        let plan = try TalkFramePlan(features: feature, bucketFrames: 77)
        var wave = Array(repeating: Float(0.5), count: 77 * 256)
        wave[0] = .nan
        XCTAssertThrowsError(try plan.crop(wave))
        let data = try TalkPCM.wav(samples: [-1, -0.5, 0, 0.5, 1])
        let wav = try SpeechWAV(data: data)
        XCTAssertEqual(wav.sampleRate, 24_000)
        XCTAssertEqual(wav.sampleCount, 5)
        XCTAssertEqual(wav.peak, 32_767)
        XCTAssertThrowsError(try TalkPCM.wav(samples: [.infinity]))
    }
}
