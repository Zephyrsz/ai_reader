import Foundation

public enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case text, txt, markdown, pdf
    public var label: String { switch self { case .text: return "文本"; case .txt: return "TXT"; case .markdown: return "MD"; case .pdf: return "PDF" } }
}

public struct ReadingPosition: Codable, Equatable, Sendable {
    public var paragraphIndex: Int = 0
    public var pageIndex: Int = 0
    public var progress: Double = 0
    public init(paragraphIndex: Int = 0, pageIndex: Int = 0, progress: Double = 0) {
        self.paragraphIndex = paragraphIndex; self.pageIndex = pageIndex; self.progress = progress
    }
}

public struct ReaderBookmark: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var paragraphIndex: Int
    public var pageIndex: Int?
    public var excerpt: String
    public var isOrphaned: Bool
    public var createdAt: Date
    public init(id: UUID = UUID(), paragraphIndex: Int, pageIndex: Int? = nil, excerpt: String, isOrphaned: Bool = false, createdAt: Date = Date()) {
        self.id = id; self.paragraphIndex = paragraphIndex; self.pageIndex = pageIndex; self.excerpt = excerpt; self.isOrphaned = isOrphaned; self.createdAt = createdAt
    }
}

public struct ReaderDocument: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var kind: DocumentKind
    public var language: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastOpenedAt: Date?
    public var contentRevision: Int
    public var isFavorite: Bool
    public var folderID: UUID?
    public var originalFilename: String?
    public var originalRelativePath: String?
    public var sourceFingerprint: String?
    public var pageTexts: [String]
    public var position: ReadingPosition
    public var bookmarks: [ReaderBookmark]
    public var deletedAt: Date?
    public var playbackRate: Double?
    public var paragraphs: [String] { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    public init(id: UUID = UUID(), title: String, text: String, kind: DocumentKind = .text, language: String = "ja-JP", createdAt: Date = Date(), folderID: UUID? = nil) {
        self.id = id; self.title = title; self.text = text; self.kind = kind; self.language = language; self.createdAt = createdAt; self.modifiedAt = createdAt
        self.lastOpenedAt = nil; self.contentRevision = 1; self.isFavorite = false; self.folderID = folderID
        self.originalFilename = nil; self.originalRelativePath = nil; self.sourceFingerprint = nil; self.pageTexts = []; self.position = ReadingPosition(); self.bookmarks = []; self.deletedAt = nil; self.playbackRate = nil
    }
}

public struct ReaderFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public enum ReaderAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var label: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}

public struct ReaderPreferences: Codable, Equatable, Sendable {
    public var appearance: ReaderAppearance = .system
    public var fontSize: Double = 20
    public var lineSpacing: Double = 10
    public var defaultRate: Double = 1
    public var followSpeech: Bool = true
    public var voice: SpeechVoice = .metan
    public init() {}
    private enum CodingKeys: String, CodingKey { case appearance, fontSize, lineSpacing, defaultRate, followSpeech, voice }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(ReaderAppearance.self, forKey: .appearance) ?? .system
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 20
        lineSpacing = try values.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 10
        defaultRate = try values.decodeIfPresent(Double.self, forKey: .defaultRate) ?? 1
        followSpeech = try values.decodeIfPresent(Bool.self, forKey: .followSpeech) ?? true
        voice = try values.decodeIfPresent(SpeechVoice.self, forKey: .voice) ?? .metan
    }
}

public struct EditorDraft: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var documentID: UUID?
    public var title: String
    public var body: String
    public var language: String
    public var folderID: UUID?
    public var updatedAt: Date
    public init(id: UUID = UUID(), documentID: UUID? = nil, title: String = "", body: String = "", language: String = "ja-JP", folderID: UUID? = nil, updatedAt: Date = Date()) {
        self.id = id; self.documentID = documentID; self.title = title; self.body = body; self.language = language; self.folderID = folderID; self.updatedAt = updatedAt
    }
}

public struct LibrarySnapshot: Sendable {
    public var documents: [ReaderDocument]
    public var folders: [ReaderFolder]
    public var preferences: ReaderPreferences
    public var drafts: [EditorDraft]
    public var loadWarnings: [String]
    public init(documents: [ReaderDocument] = [], folders: [ReaderFolder] = [], preferences: ReaderPreferences = ReaderPreferences(), drafts: [EditorDraft] = [], loadWarnings: [String] = []) {
        self.documents = documents; self.folders = folders; self.preferences = preferences; self.drafts = drafts; self.loadWarnings = loadWarnings
    }
}

public struct StorageUsage: Sendable {
    public var documents: Int64
    public var drafts: Int64
    public var caches: Int64
    public var total: Int64 { documents + drafts + caches }
    public init(documents: Int64 = 0, drafts: Int64 = 0, caches: Int64 = 0) { self.documents = documents; self.drafts = drafts; self.caches = caches }
}

public enum RepositoryError: Error, LocalizedError, Equatable {
    case emptyText, missingDocument, invalidFolder, invalidName, unsupportedFile, fileTooLarge, textTooLong, tooManyPages, duplicate(UUID), notInTrash, invalidEncoding, unavailable
    public var errorDescription: String? {
        switch self {
        case .emptyText: return "正文不能为空。"
        case .missingDocument: return "资料不存在或已被删除。"
        case .invalidFolder: return "目标文件夹不存在。"
        case .invalidName: return "名称不能为空，且不能包含路径分隔符。"
        case .unsupportedFile: return "目前支持 PDF、TXT 和 MD 文件。"
        case .fileTooLarge: return "单个文件不能超过 50 MB。"
        case .textTooLong: return "文本不能超过 20 万个字符。"
        case .tooManyPages: return "PDF 不能超过 1000 页。"
        case .duplicate: return "此文件已在资料库中。"
        case .notInTrash: return "请先将资料移入最近删除。"
        case .invalidEncoding: return "无法按此编码读取文本，请选择其他编码。"
        case .unavailable: return "语音引擎尚未接入。"
        }
    }
}
