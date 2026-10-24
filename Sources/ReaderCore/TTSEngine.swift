import Foundation

/// Device-only synthesis boundary. LocalSpeechService supplies native Japanese speech.
public protocol TTSEngine: Sendable {
    var supportedLanguages: [String] { get }
    func prepare(language: String) async throws
    func synthesize(text: String, language: String, rate: Double) async throws -> URL
    func cancel() async
}

/// Deliberately does not generate audio or simulate playback.
public struct UnavailableTTSEngine: TTSEngine {
    public let supportedLanguages: [String] = []
    public init() {}
    public func prepare(language: String) async throws { throw RepositoryError.unavailable }
    public func synthesize(text: String, language: String, rate: Double) async throws -> URL { throw RepositoryError.unavailable }
    public func cancel() async {}
}
