import Foundation

public enum SpeechVoice: UInt32, Codable, CaseIterable, Identifiable, Sendable {
    case metan = 0, tsumugi = 8, himari = 14, whiteCUL = 24
    public var id: UInt32 { rawValue }
    public var name: String {
        switch self { case .metan: return "四国めたん"; case .tsumugi: return "春日部つむぎ"; case .himari: return "冥鳴ひまり"; case .whiteCUL: return "WhiteCUL" }
    }
    public var style: String {
        switch self { case .metan: return "あまあま"; case .tsumugi, .himari: return "ノーマル"; case .whiteCUL: return "たのしい" }
    }
    public var modelFile: String {
        switch self { case .metan, .tsumugi: return "0.vvm"; case .himari: return "1.vvm"; case .whiteCUL: return "8.vvm" }
    }
    public var credit: String { "VOICEVOX:\(name)" }
}

public enum SpeechError: Error, LocalizedError, Equatable {
    case unsupportedLanguage, invalidText, invalidRate, busy, invalidAudio, segmentTooLong
    case resource(String), native(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedLanguage: return "本机语音目前支持日语（ja-JP）。此资料仍可正常阅读。"
        case .invalidText: return "朗读文本为空、过长或包含不支持的控制字符。"
        case .invalidRate: return "语速必须在 0.5–2.0 倍之间。"
        case .busy: return "语音正在准备，请稍后重试。"
        case .invalidAudio: return "本机语音输出无效，请重试。"
        case .segmentTooLong: return "这句话的预计音频过长，请在标点或停顿处拆分后重试。"
        case .resource(let message): return "语音资源不可用：\(message)"
        case .native(let message): return "本机语音合成失败：\(message)"
        }
    }
}

public struct SpeechRequest: Codable, Equatable, Sendable {
    public let text: String
    public let language: String
    public let voice: SpeechVoice
    public let rate: Double
    public init(text: String, language: String, voice: SpeechVoice, rate: Double) throws {
        guard language == "ja-JP" else { throw SpeechError.unsupportedLanguage }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500, !trimmed.contains("\0") else { throw SpeechError.invalidText }
        guard rate.isFinite, (0.5...2).contains(rate) else { throw SpeechError.invalidRate }
        self.text = trimmed; self.language = language; self.voice = voice; self.rate = rate
    }
}

public struct SpeechSegment: Equatable, Sendable, Identifiable {
    public let id: Int
    public let text: String
    public let paragraphIndex: Int
}

public enum JapaneseSpeechSegmenter {
    public static func segments(paragraphs: [String], maximumCharacters: Int = 60) -> [SpeechSegment] {
        let limit = max(8, maximumCharacters)
        let terminals: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
        let closers: Set<Character> = ["」", "』", "）", ")", "】", "”", "\"", "’"]
        let breaks: Set<Character> = ["、", "，", ",", " ", "\t", "；", ";"]
        var result: [SpeechSegment] = []
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let chars = Array(paragraph)
            var start = 0
            while start < chars.count {
                var end = start
                var lastBreak: Int?
                while end < chars.count {
                    let char = chars[end]
                    end += 1
                    if breaks.contains(char) { lastBreak = end }
                    if terminals.contains(char) {
                        while end < chars.count && end - start < limit && (closers.contains(chars[end]) || terminals.contains(chars[end])) { end += 1 }
                        break
                    }
                    if end - start >= limit {
                        if let candidate = lastBreak, candidate - start >= limit / 2 { end = candidate }
                        break
                    }
                }
                let text = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.append(SpeechSegment(id: result.count, text: text, paragraphIndex: paragraphIndex)) }
                start = end
            }
        }
        return result
    }
}
