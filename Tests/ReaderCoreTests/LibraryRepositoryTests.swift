import XCTest
@testable import ReaderCore

final class LibraryRepositoryTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AIReader-tests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testJapaneseTextSurvivesRepositoryReopenAndGetsTitleFromBody() async throws {
        let url = try root(); let repo = try LibraryRepository(root: url)
        let document = try await repo.createText(title: "  ", body: "おはようございます。\n京都の朝です。")
        XCTAssertEqual(document.title, "おはようございます。")
        let reopened = try LibraryRepository(root: url)
        let snapshot = await reopened.snapshot()
        XCTAssertEqual(snapshot.documents.count, 1)
        XCTAssertEqual(snapshot.documents.first?.text, "おはようございます。\n京都の朝です。")
        XCTAssertEqual(snapshot.documents.first?.language, "ja-JP")
    }

    func testWhitespaceOnlyTextIsRejectedWithoutCreatingDocument() async throws {
        let repo = try LibraryRepository(root: root())
        do { _ = try await repo.createText(title: "空", body: " \n\t"); XCTFail("Empty text accepted") }
        catch { XCTAssertEqual(error as? RepositoryError, .emptyText) }
        let snapshot = await repo.snapshot(); XCTAssertTrue(snapshot.documents.isEmpty)
    }

    func testBodyEditInvalidatesPositionAndPreservesOrphanBookmarkExcerpt() async throws {
        let repo = try LibraryRepository(root: root())
        let document = try await repo.createText(title: "日記", body: "朝です。\n駅へ行きます。")
        try await repo.addBookmark(id: document.id, paragraphIndex: 1)
        try await repo.setPosition(id: document.id, position: ReadingPosition(paragraphIndex: 1, progress: 0.8))
        let changed = try await repo.updateText(id: document.id, title: "日記", body: "夕方です。")
        XCTAssertEqual(changed.contentRevision, 2)
        XCTAssertEqual(changed.position.progress, 0)
        XCTAssertEqual(changed.bookmarks.first?.excerpt, "駅へ行きます。")
        XCTAssertEqual(changed.bookmarks.first?.isOrphaned, true)
        let renamed = try await repo.updateText(id: document.id, title: "夕方", body: "夕方です。")
        XCTAssertEqual(renamed.contentRevision, 2, "Changing only a title must not invalidate content")
    }

    func testImportCopiesOriginalAndRejectsContentDuplicateEvenWithDifferentFilename() async throws {
        let url = try root(); let repo = try LibraryRepository(root: url.appendingPathComponent("library"))
        let source = url.appendingPathComponent("first.txt"); try Data("日本語".utf8).write(to: source)
        let imported = try await repo.importDocument(sourceURL: source, text: "日本語", kind: .txt)
        let original = try await repo.originalURL(for: imported.id)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "日本語")
        let duplicate = url.appendingPathComponent("second.txt"); try Data("日本語".utf8).write(to: duplicate)
        do { _ = try await repo.importDocument(sourceURL: duplicate, text: "日本語", kind: .txt); XCTFail("Duplicate imported") }
        catch { XCTAssertEqual(error as? RepositoryError, .duplicate(imported.id)) }
        _ = try await repo.importDocument(sourceURL: duplicate, text: "日本語", kind: .txt, allowDuplicate: true)
        let snapshot = await repo.snapshot(); XCTAssertEqual(snapshot.documents.count, 2)
    }

    func testTrashRestoreAndExpiryNeverDeleteActiveDocuments() async throws {
        let repo = try LibraryRepository(root: root())
        let active = try await repo.createText(title: "保留", body: "保留します。")
        let expired = try await repo.createText(title: "削除", body: "削除します。")
        try await repo.trash(ids: [active.id]); try await repo.restore(ids: [active.id])
        try await repo.trash(ids: [expired.id], now: Date().addingTimeInterval(-31 * 86400))
        try await repo.purgeExpiredTrash()
        let snapshot = await repo.snapshot()
        XCTAssertEqual(snapshot.documents.map(\.id), [active.id])
        XCTAssertNil(snapshot.documents.first?.deletedAt)
        do { try await repo.deletePermanently(ids: [active.id]); XCTFail("Active data permanently deleted") }
        catch { XCTAssertEqual(error as? RepositoryError, .notInTrash) }
    }

    func testDeletingFolderMovesDocumentsToRootWithoutDeletingContent() async throws {
        let repo = try LibraryRepository(root: root())
        let folder = try await repo.addFolder(name: "日语学习")
        let document = try await repo.createText(title: "文", body: "本文", folderID: folder.id)
        try await repo.deleteFolder(id: folder.id)
        let snapshot = await repo.snapshot()
        XCTAssertTrue(snapshot.folders.isEmpty)
        XCTAssertEqual(snapshot.documents.first?.id, document.id)
        XCTAssertNil(snapshot.documents.first?.folderID)
    }

    func testDraftPreferencesAndBookmarkPersistAndCacheCleanupKeepsContent() async throws {
        let url = try root(); let repo = try LibraryRepository(root: url)
        let document = try await repo.createText(title: "朝", body: "朝です。")
        try await repo.addBookmark(id: document.id, paragraphIndex: 0)
        let draft = EditorDraft(title: "未完成", body: "途中です。")
        try await repo.saveDraft(draft)
        var preferences = ReaderPreferences(); preferences.fontSize = 28; preferences.appearance = .dark
        try await repo.setPreferences(preferences)
        let cache = url.appendingPathComponent("Caches"); try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: cache.appendingPathComponent("temporary"))
        try await repo.clearCaches()
        let reopened = try LibraryRepository(root: url); let snapshot = await reopened.snapshot()
        XCTAssertEqual(snapshot.documents.first?.bookmarks.count, 1)
        XCTAssertEqual(snapshot.drafts.first?.body, "途中です。")
        XCTAssertEqual(snapshot.preferences.fontSize, 28)
        XCTAssertEqual(snapshot.preferences.appearance, .dark)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.appendingPathComponent("temporary").path))
    }

    func testCorruptDocumentIsReportedAndNeverOverwrittenOnLoad() async throws {
        let url = try root(); let documents = url.appendingPathComponent("Documents/\(UUID())")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let file = documents.appendingPathComponent("document.json"); let corrupt = Data("not-json".utf8); try corrupt.write(to: file)
        let repo = try LibraryRepository(root: url); let snapshot = await repo.snapshot()
        XCTAssertFalse(snapshot.loadWarnings.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testFailedWriteDoesNotReplaceInMemoryDocument() async throws {
        let url = try root(); let repo = try LibraryRepository(root: url)
        let document = try await repo.createText(title: "原稿", body: "保存済み")
        let directory = url.appendingPathComponent("Documents/\(document.id.uuidString)")
        try FileManager.default.removeItem(at: directory); try Data([1]).write(to: directory)
        do { _ = try await repo.updateText(id: document.id, title: "変更", body: "失敗する変更"); XCTFail("Write should fail") } catch { }
        let snapshot = await repo.snapshot(); XCTAssertEqual(snapshot.documents.first?.text, "保存済み")
    }

    func testImportLimitsAndEmptyScannedPDF() async throws {
        let url = try root(); let repo = try LibraryRepository(root: url.appendingPathComponent("library"))
        let source = url.appendingPathComponent("scan.pdf"); try Data("%PDF-example".utf8).write(to: source)
        let scanned = try await repo.importDocument(sourceURL: source, text: "", kind: .pdf, pageTexts: [""])
        XCTAssertEqual(scanned.pageTexts, [""])
        do { _ = try await repo.importDocument(sourceURL: source, text: "", kind: .pdf, pageTexts: Array(repeating: "", count: 301), allowDuplicate: true); XCTFail("Overlong PDF accepted") }
        catch { XCTAssertEqual(error as? RepositoryError, .tooManyPages) }
        do { _ = try await repo.createText(title: "long", body: String(repeating: "あ", count: 200_001)); XCTFail("Text limit ignored") }
        catch { XCTAssertEqual(error as? RepositoryError, .textTooLong) }
    }
}
