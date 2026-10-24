import Foundation
import Observation
import ReaderCore
import SwiftUI

public enum AppTab: Hashable { case home, library, settings }

public struct ImportRequest: Identifiable, Equatable {
    public let id = UUID()
    public let urls: [URL]
    public init(urls: [URL]) { self.urls = urls }
    public static func == (lhs: ImportRequest, rhs: ImportRequest) -> Bool { lhs.id == rhs.id }
}

@MainActor @Observable
public final class AppStore {
    let playback = SpeechPlaybackCoordinator.makeDefault()
    public let repository: LibraryRepository
    public var snapshot: LibrarySnapshot
    public var errorMessage: String?
    public var homePath: [UUID] = []
    public var libraryPath: [UUID] = []
    public var settingsPath: [UUID] = []
    public var editorDraft: EditorDraft?
    public var importRequest: ImportRequest?
    public var showFileImporter = false
    public var selectedTab: AppTab = .home
    public var startupBlockedMessage: String?

    public var preferences: ReaderPreferences { snapshot.preferences }
    public var documents: [ReaderDocument] { snapshot.documents.filter { $0.deletedAt == nil } }

    public init(repository: LibraryRepository) {
        self.repository = repository
        self.snapshot = LibrarySnapshot()
        playback.onParagraph = { [weak self] id, paragraph in
            guard let self, let document = self.document(id) else { return }
            let position = ReadingPosition(paragraphIndex: paragraph, pageIndex: document.position.pageIndex, progress: Double(paragraph) / Double(max(1, document.paragraphs.count)))
            Task { _ = await self.perform { try await $0.setPosition(id: id, position: position) } }
        }
        Task { await refresh() }
    }

    public static func makeDefault() -> AppStore? {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var root = base.appendingPathComponent("AIReader", isDirectory: true)
            #if DEBUG
            if let testLibrary = ProcessInfo.processInfo.environment["AI_READER_TEST_LIBRARY"],
               testLibrary.hasPrefix("UITests-"),
               testLibrary.unicodeScalars.allSatisfy({
                   (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || $0.value == 45
               }) {
                root = base.appendingPathComponent(testLibrary, isDirectory: true)
            }
            #endif
            let repository = try LibraryRepository(root: root)
            return AppStore(repository: repository)
        } catch {
            return nil
        }
    }

    public func document(_ id: UUID) -> ReaderDocument? { documents.first { $0.id == id } }

    public func refresh() async {
        var refreshError: String?
        do { try await repository.purgeExpiredTrash() }
        catch { refreshError = error.localizedDescription }
        snapshot = await repository.snapshot()
        playback.reconcile(documents: snapshot.documents, preferences: snapshot.preferences)
        if let refreshError { errorMessage = refreshError }
        else if !snapshot.loadWarnings.isEmpty { errorMessage = snapshot.loadWarnings.joined(separator: "\n") }
        else { errorMessage = nil }
    }

    @discardableResult
    public func perform(_ operation: (LibraryRepository) async throws -> Void) async -> Bool {
        var succeeded = true
        var operationError: String?
        do {
            try await operation(repository)
        } catch {
            succeeded = false
            operationError = error.localizedDescription
        }
        snapshot = await repository.snapshot()
        playback.reconcile(documents: snapshot.documents, preferences: snapshot.preferences)
        errorMessage = operationError ?? (snapshot.loadWarnings.isEmpty ? nil : snapshot.loadWarnings.joined(separator: "\n"))
        return succeeded
    }

    public func openDocument(_ id: UUID) {
        let sourceTab = selectedTab
        Task {
            guard await perform({ try await $0.recordOpened(id: id) }) else { return }
            switch sourceTab {
            case .home: homePath.append(id)
            case .library: libraryPath.append(id)
            case .settings: settingsPath.append(id)
            }
        }
    }

    public func newText(body: String = "", folderID: UUID? = nil) {
        editorDraft = EditorDraft(body: body, folderID: folderID)
    }

    public func editDocument(_ document: ReaderDocument) {
        if playback.documentID == document.id { playback.stop() }
        editorDraft = EditorDraft(id: UUID(), documentID: document.id, title: document.title, body: document.text, language: document.language, folderID: document.folderID)
    }

    public func savePreferences(_ preferences: ReaderPreferences) async {
        _ = await perform { try await $0.setPreferences(preferences) }
    }
}
