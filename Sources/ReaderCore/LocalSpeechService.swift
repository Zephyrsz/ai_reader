import Foundation
import CryptoKit

/// Implementations are owned by LocalSpeechService and called only on its serial queue.
public protocol SpeechRuntime: AnyObject, Sendable {
    var cacheIdentity: String { get }
    func prepare() throws
    func synthesize(_ request: SpeechRequest) throws -> Data
    func releaseResources()
}

/// All native calls and cache I/O run off the main thread. Invalidation is immediate;
/// an active synchronous inference completes, then its stale output is discarded.
public final class LocalSpeechService: TTSEngine, @unchecked Sendable {
    public let supportedLanguages = ["ja-JP"]
    private let runtime: any SpeechRuntime
    private let queue = DispatchQueue(label: "dev.aireader.speech", qos: .userInitiated)
    private let state = SpeechQueueState()
    private let cacheDirectory: URL
    private let cacheBudget: Int

    public init(runtime: any SpeechRuntime, cacheDirectory: URL, cacheBudget: Int = 96 * 1024 * 1024) {
        self.runtime = runtime; self.cacheDirectory = cacheDirectory; self.cacheBudget = max(0, cacheBudget)
    }

    public func prepare(language: String) async throws {
        guard supportedLanguages.contains(language) else { throw SpeechError.unsupportedLanguage }
        try await submit { try self.runtime.prepare() }
    }

    public func synthesize(text: String, language: String, rate: Double) async throws -> URL {
        try await synthesize(text: text, language: language, voice: .metan, rate: rate)
    }

    public func synthesize(text: String, language: String, voice: SpeechVoice, rate: Double) async throws -> URL {
        let request = try SpeechRequest(text: text, language: language, voice: voice, rate: rate)
        return try await submit { ticket in
            try self.runtime.prepare()
            try self.state.check(ticket)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var identity = Data(self.runtime.cacheIdentity.utf8)
            identity.append(try encoder.encode(request))
            let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
            let url = self.cacheDirectory.appendingPathComponent(key + ".wav")
            if let data = try? Data(contentsOf: url), (try? SpeechWAV(data: data)) != nil {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
                return url
            }
            let data = try self.runtime.synthesize(request)
            _ = try SpeechWAV(data: data)
            try self.state.check(ticket)
            // A preferred backend may have fallen back while synthesizing. Use
            // the effective backend identity for the generated file, never the
            // identity that was only used for the cache lookup.
            var effectiveIdentity = Data(self.runtime.cacheIdentity.utf8)
            effectiveIdentity.append(try encoder.encode(request))
            let effectiveKey = SHA256.hash(data: effectiveIdentity).map { String(format: "%02x", $0) }.joined()
            let effectiveURL = self.cacheDirectory.appendingPathComponent(effectiveKey + ".wav")
            try FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: effectiveURL, options: .atomic)
            try self.trimCache(keeping: effectiveURL)
            return effectiveURL
        }
    }

    public func cancel() async { invalidate() }
    public func invalidate() { state.invalidate() }
    public func releaseResources() { queue.async { self.runtime.releaseResources() } }

    public func clearCache() async throws {
        try await submit {
            if FileManager.default.fileExists(atPath: self.cacheDirectory.path) { try FileManager.default.removeItem(at: self.cacheDirectory) }
        }
    }

    public func cacheSize() async throws -> Int {
        try await submit {
            try self.cacheFiles().reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        }
    }

    private func cacheFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]).filter { $0.pathExtension == "wav" }
    }

    private func trimCache(keeping current: URL) throws {
        let files = try cacheFiles().map { ($0, try $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])) }
        var size = files.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
        for (url, values) in files.sorted(by: { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }) where size > cacheBudget && url != current {
            try FileManager.default.removeItem(at: url); size -= values.fileSize ?? 0
        }
    }

    private func submit<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await submit { _ in try work() }
    }

    private func submit<T: Sendable>(_ work: @escaping @Sendable (SpeechTicket) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let ticket = try state.admit()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    defer { self.state.finish(ticket) }
                    do {
                        try self.state.check(ticket)
                        let result = try work(ticket)
                        try self.state.check(ticket)
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { ticket.cancel() }
    }
}

private final class SpeechTicket: @unchecked Sendable {
    let generation: UInt64
    private let lock = NSLock()
    private var cancelled = false
    init(generation: UInt64) { self.generation = generation }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private final class SpeechQueueState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var pending = 0
    func admit() throws -> SpeechTicket {
        lock.lock(); defer { lock.unlock() }
        guard pending < 3 else { throw SpeechError.busy }
        pending += 1; return SpeechTicket(generation: generation)
    }
    func check(_ ticket: SpeechTicket) throws {
        lock.lock(); let current = generation; lock.unlock()
        if current != ticket.generation || ticket.isCancelled { throw CancellationError() }
    }
    func finish(_ ticket: SpeechTicket) {
        lock.lock(); defer { lock.unlock() }
        if generation == ticket.generation { pending -= 1 }
    }
    func invalidate() { lock.lock(); generation &+= 1; pending = 0; lock.unlock() }
}
