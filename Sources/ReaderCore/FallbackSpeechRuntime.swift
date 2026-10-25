import Foundation

public struct SpeechRuntimeDiagnostics: Sendable, Equatable {
    public let requestedBackend: String
    public fileprivate(set) var selectedBackend: String
    public fileprivate(set) var fallbackReason: String?

    fileprivate init(requestedBackend: String) {
        self.requestedBackend = requestedBackend
        selectedBackend = requestedBackend
    }
}

/// Tries an optional accelerator once, then keeps the process on CPU after a
/// non-cancellation failure. Both runtimes are called by LocalSpeechService's
/// serial queue, so this type does not add a second execution queue.
public final class FallbackSpeechRuntime: SpeechRuntime, @unchecked Sendable {
    private enum Active { case preferred, fallback }

    private let preferred: any SpeechRuntime
    private let fallback: any SpeechRuntime
    private var active: Active?
    private var stickyFallback = false
    private let stateLock = NSLock()
    private var _diagnostics: SpeechRuntimeDiagnostics

    public init(preferred: any SpeechRuntime, fallback: any SpeechRuntime, requestedBackend: String = "CoreML") {
        self.preferred = preferred
        self.fallback = fallback
        _diagnostics = SpeechRuntimeDiagnostics(requestedBackend: requestedBackend)
    }

    public var cacheIdentity: String {
        switch active {
        case .fallback: return fallback.cacheIdentity
        case .preferred: return preferred.cacheIdentity
        case nil: return stickyFallback ? fallback.cacheIdentity : preferred.cacheIdentity
        }
    }

    public var diagnostics: SpeechRuntimeDiagnostics {
        stateLock.lock(); defer { stateLock.unlock() }
        return _diagnostics
    }

    public func prepare() throws {
        if stickyFallback {
            if active == .fallback { return }
            try prepareFallback()
            return
        }
        if active != nil { return }
        do {
            try preferred.prepare()
            active = .preferred
            stateLock.lock(); _diagnostics.selectedBackend = _diagnostics.requestedBackend; stateLock.unlock()
        } catch {
            if error is CancellationError { preferred.releaseResources(); throw error }
            activateFallback(after: error)
            try prepareFallback()
        }
    }

    public func synthesize(_ request: SpeechRequest) throws -> Data {
        try prepare()
        guard active != nil else { throw SpeechError.native("语音运行时未就绪") }
        if active == .fallback { return try fallback.synthesize(request) }
        do {
            return try preferred.synthesize(request)
        } catch {
            if error is CancellationError { throw error }
            activateFallback(after: error)
            try prepareFallback()
            return try fallback.synthesize(request)
        }
    }

    public func releaseResources() {
        if active == .fallback || stickyFallback {
            fallback.releaseResources()
        } else if active == .preferred {
            preferred.releaseResources()
        }
        active = nil
    }

    private func activateFallback(after error: Error) {
        preferred.releaseResources()
        stickyFallback = true
        active = nil
        stateLock.lock()
        _diagnostics.selectedBackend = "CPU"
        _diagnostics.fallbackReason = error.localizedDescription
        stateLock.unlock()
    }

    private func prepareFallback() throws {
        do {
            try fallback.prepare()
            active = .fallback
        } catch {
            fallback.releaseResources()
            active = nil
            throw error
        }
        stateLock.lock(); _diagnostics.selectedBackend = "CPU"; stateLock.unlock()
    }
}
