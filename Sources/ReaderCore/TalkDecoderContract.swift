import Foundation

/// Unpadded Talk features. This is deliberately not AudioQuery or a style ID.
public struct TalkFrameFeatures: Sendable {
    public static let maximumFrames = 2_812 // <= 30 seconds at 24k / 256
    public let f0: [Float]
    public let phoneme: [Float]
    public let speakerID: Int64
    public var frameCount: Int { f0.count }

    public init(f0: [Float], phoneme: [Float], speakerID: Int64) throws {
        guard (1...Self.maximumFrames).contains(f0.count), phoneme.count == f0.count * 45,
              f0.allSatisfy({ $0.isFinite && $0 >= 0 }), phoneme.allSatisfy(\.isFinite),
              (0...Int64(Int32.max)).contains(speakerID) else {
            throw SpeechError.resource("Talk 帧特征的长度、类型或内部音色 ID 无效")
        }
        self.f0 = f0; self.phoneme = phoneme; self.speakerID = speakerID
    }
}

public struct TalkFramePlan: Sendable {
    public static let maximumBucketFrames = 8_192
    public let bucketFrames: Int
    public let effectiveFrames: Int
    public let f0: [Float]
    public let phoneme: [Float]

    public init(features: TalkFrameFeatures, bucketFrames: Int) throws {
        guard (features.frameCount + 76...Self.maximumBucketFrames).contains(bucketFrames) else {
            throw SpeechError.segmentTooLong
        }
        self.bucketFrames = bucketFrames; effectiveFrames = features.frameCount
        var paddedF0 = [Float](repeating: 0, count: bucketFrames)
        var paddedPhoneme = [Float](repeating: 0, count: bucketFrames * 45)
        for frame in 0..<bucketFrames { paddedPhoneme[frame * 45] = 1 }
        paddedF0.replaceSubrange(38..<(38 + features.frameCount), with: features.f0)
        paddedPhoneme.replaceSubrange((38 * 45)..<((38 + features.frameCount) * 45), with: features.phoneme)
        f0 = paddedF0; phoneme = paddedPhoneme
    }

    public func crop(_ wave: [Float]) throws -> [Float] {
        guard wave.count == bucketFrames * 256, wave.allSatisfy(\.isFinite) else { throw SpeechError.invalidAudio }
        return Array(wave[(38 * 256)..<((38 + effectiveFrames) * 256)])
    }
}

public enum TalkPCM {
    public static func wav(samples: [Float]) throws -> Data {
        guard !samples.isEmpty, samples.count <= TalkFrameFeatures.maximumFrames * 256,
              samples.allSatisfy(\.isFinite) else { throw SpeechError.invalidAudio }
        var data = Data("RIFF".utf8)
        func u16(_ value: UInt16) { var x = value.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var x = value.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        u32(UInt32(36 + samples.count * 2)); data.append(Data("WAVEfmt ".utf8)); u32(16)
        u16(1); u16(1); u32(24_000); u32(48_000); u16(2); u16(16)
        data.append(Data("data".utf8)); u32(UInt32(samples.count * 2))
        for sample in samples { u16(UInt16(bitPattern: Int16((max(-1, min(1, sample)) * 32_767).rounded()))) }
        return data
    }
}
