import Foundation

public enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, text, pdf, favorites
    public var id: String { rawValue }
    public var label: String { switch self { case .all: return "全部"; case .text: return "文本"; case .pdf: return "PDF"; case .favorites: return "收藏" } }
}
public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recentlyOpened, dateAdded, title
    public var id: String { rawValue }
    public var label: String { switch self { case .recentlyOpened: return "最近打开"; case .dateAdded: return "添加时间"; case .title: return "标题" } }
}
public enum LibraryQuery {
    public static func apply(documents: [ReaderDocument], search: String = "", filter: LibraryFilter = .all, sort: LibrarySort = .recentlyOpened, folderID: UUID? = nil, showDeleted: Bool = false) -> [ReaderDocument] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return documents.filter { document in
            guard (document.deletedAt != nil) == showDeleted,
                  folderID == nil || document.folderID == folderID else { return false }
            switch filter {
            case .all: break
            case .text: guard document.kind != .pdf else { return false }
            case .pdf: guard document.kind == .pdf else { return false }
            case .favorites: guard document.isFavorite else { return false }
            }
            return query.isEmpty || document.title.localizedCaseInsensitiveContains(query) || document.text.localizedCaseInsensitiveContains(query)
        }.sorted { lhs, rhs in
            switch sort {
            case .recentlyOpened:
                let left = lhs.lastOpenedAt ?? lhs.createdAt, right = rhs.lastOpenedAt ?? rhs.createdAt
                if left != right { return left > right }
            case .dateAdded:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
