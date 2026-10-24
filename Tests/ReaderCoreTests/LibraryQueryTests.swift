import XCTest
@testable import ReaderCore

final class LibraryQueryTests: XCTestCase {
    func testSearchIncludesJapaneseBodyAndExcludesTrash() {
        let active = ReaderDocument(title: "日記", text: "京都の朝")
        var deleted = ReaderDocument(title: "京都", text: "削除済み"); deleted.deletedAt = Date()
        let result = LibraryQuery.apply(documents: [active, deleted], search: " 京都 ")
        XCTAssertEqual(result.map(\.id), [active.id])
        XCTAssertEqual(LibraryQuery.apply(documents: [active, deleted], showDeleted: true).map(\.id), [deleted.id])
    }
    func testFolderFavoritesAndTypeFiltersCombineWithoutLeakingOtherDocuments() {
        let folderID = UUID()
        var favorite = ReaderDocument(title: "PDF", text: "本文", kind: .pdf, folderID: folderID); favorite.isFavorite = true
        let text = ReaderDocument(title: "文", text: "本文", folderID: folderID)
        let outside = ReaderDocument(title: "別", text: "本文", kind: .pdf)
        let documents = [favorite, text, outside]
        XCTAssertEqual(LibraryQuery.apply(documents: documents, filter: .favorites, folderID: folderID).map(\.id), [favorite.id])
        XCTAssertEqual(LibraryQuery.apply(documents: documents, filter: .text).map(\.id), [text.id])
        XCTAssertEqual(LibraryQuery.apply(documents: documents, filter: .pdf, folderID: folderID).map(\.id), [favorite.id])
    }
    func testRecentSortUsesLastOpenWhileDateAddedUsesCreation() {
        var earlier = ReaderDocument(title: "A", text: "本文", createdAt: Date(timeIntervalSince1970: 100))
        earlier.lastOpenedAt = Date(timeIntervalSince1970: 300)
        let newer = ReaderDocument(title: "B", text: "本文", createdAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(LibraryQuery.apply(documents: [newer, earlier]).map(\.title), ["A", "B"])
        XCTAssertEqual(LibraryQuery.apply(documents: [earlier, newer], sort: .dateAdded).map(\.title), ["B", "A"])
    }
}
