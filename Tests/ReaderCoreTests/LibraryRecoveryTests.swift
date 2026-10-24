import XCTest
@testable import ReaderCore

final class LibraryRecoveryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("AIReader-Recovery-\(UUID())")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }
        return parent.appendingPathComponent("Library")
    }

    func testInterruptedResetRecoversTheOriginalLibraryBeforeOpening() async throws {
        let root = try temporaryRoot()
        let repo = try LibraryRepository(root: root)
        let doc = try await repo.createText(title: "大切な文章", body: "消さないでください。")
        let backupName = "Library-reset-old-\(UUID())"
        let backup = root.deletingLastPathComponent().appendingPathComponent(backupName)
        let marker = root.deletingLastPathComponent().appendingPathComponent("Library.reset-recovery.json")
        try JSONSerialization.data(withJSONObject: ["backup": backupName]).write(to: marker)
        try FileManager.default.moveItem(at: root, to: backup)
        let reopened = try LibraryRepository(root: root)
        let result = await reopened.snapshot()
        XCTAssertEqual(result.documents.first?.id, doc.id)
        XCTAssertEqual(result.documents.first?.text, "消さないでください。")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testResetPreparationFailurePreservesAllExistingData() async throws {
        let root = try temporaryRoot()
        let repo = try LibraryRepository(root: root)
        let doc = try await repo.createText(title: "原稿", body: "原本を保つ。")
        let marker = root.deletingLastPathComponent().appendingPathComponent("Library.reset-recovery.json")
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        do { try await repo.resetLibrary(); XCTFail("A blocked recovery marker must abort reset before moving original data.") }
        catch { }
        let result = await repo.snapshot()
        XCTAssertEqual(result.documents.first?.id, doc.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents/\(doc.id)/document.json").path))
    }

    func testCompletedResetPersistsEmptyLibraryAndDefaultPreferences() async throws {
        let root = try temporaryRoot()
        let repo = try LibraryRepository(root: root)
        _ = try await repo.createText(title: "原稿", body: "本文")
        var preferences = ReaderPreferences(); preferences.appearance = .dark
        try await repo.setPreferences(preferences)
        try await repo.resetLibrary()
        let reopened = try LibraryRepository(root: root)
        let result = await reopened.snapshot()
        XCTAssertTrue(result.documents.isEmpty)
        XCTAssertEqual(result.preferences.appearance, .system)
    }
}
