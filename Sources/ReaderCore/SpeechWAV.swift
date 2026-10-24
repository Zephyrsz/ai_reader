import Foundation

/// Reads RIFF chunks rather than assuming the data always starts at byte 44.
public struct SpeechWAV: Sendable {
    public let sampleRate: Int
    public let sampleCount: Int
    public let peak: Int
    public var duration: Double { Double(sampleCount) / Double(sampleRate) }

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        func string(_ offset: Int, _ count: Int) -> String { String(bytes: bytes[offset..<(offset + count)], encoding: .ascii) ?? "" }
        func number(_ offset: Int, _ count: Int) -> Int { (0..<count).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) } }
        guard bytes.count >= 44, string(0, 4) == "RIFF", string(8, 4) == "WAVE",
              number(4, 4) + 8 == bytes.count else { throw SpeechError.invalidAudio }
        var offset = 12
        var rate: Int?
        var audio: Range<Int>?
        while offset + 8 <= bytes.count {
            let size = number(offset + 4, 4)
            let body = offset + 8
            guard size <= bytes.count - body else { throw SpeechError.invalidAudio }
            if string(offset, 4) == "fmt " {
                guard size >= 16, number(body, 2) == 1, number(body + 2, 2) == 1,
                      number(body + 14, 2) == 16 else { throw SpeechError.invalidAudio }
                rate = number(body + 4, 4)
            } else if string(offset, 4) == "data" { audio = body..<(body + size) }
            offset = body + size + size % 2
        }
        guard let rate, rate == 24_000, let audio, !audio.isEmpty, audio.count % 2 == 0 else { throw SpeechError.invalidAudio }
        var peak = 0
        for i in stride(from: audio.lowerBound, to: audio.upperBound, by: 2) {
            peak = max(peak, abs(Int(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))))
        }
        self.sampleRate = rate; sampleCount = audio.count / 2; self.peak = peak
    }
}
