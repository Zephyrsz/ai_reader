import Foundation
import CryptoKit

public actor LibraryRepository {
    public nonisolated let root: URL
    private var records: [UUID: ReaderDocument]
    private var draftRecords: [UUID: EditorDraft]
    private var catalog: Catalog
    private var loadWarnings: [String]
    private let fileManager = FileManager.default

    private struct Catalog: Codable {
        var schemaVersion = 1
        var folders: [ReaderFolder] = []
        var preferences = ReaderPreferences()
    }

    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        let fm = FileManager.default
        try Self.recoverInterruptedReset(root: self.root, fileManager: fm)
        for name in ["Documents", "Drafts", "Caches"] {
            try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let catalogURL = root.appendingPathComponent("library.json")
        let loadedCatalog: Catalog
        if fm.fileExists(atPath: catalogURL.path) {
            loadedCatalog = try Self.decoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
            guard loadedCatalog.schemaVersion == 1 else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "资料库版本较新，请使用兼容版本打开。原数据未被改动。"])
            }
        } else { loadedCatalog = Catalog() }
        self.catalog = loadedCatalog
        var loaded: [UUID: ReaderDocument] = [:]
        var drafts: [UUID: EditorDraft] = [:]
        var warnings: [String] = []
        let dirs = try fm.contentsOfDirectory(at: root.appendingPathComponent("Documents"), includingPropertiesForKeys: nil)
        for directory in dirs {
            let file = directory.appendingPathComponent("document.json")
            do {
                let record = try Self.decoder().decode(ReaderDocument.self, from: Data(contentsOf: file))
                guard directory.lastPathComponent == record.id.uuidString else { throw CocoaError(.fileReadCorruptFile) }
                loaded[record.id] = record
            } catch { warnings.append("无法读取资料 \(directory.lastPathComponent)。原文件已保留，请备份后检查。") }
        }
        for file in try fm.contentsOfDirectory(at: root.appendingPathComponent("Drafts"), includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            do {
                let draft = try Self.decoder().decode(EditorDraft.self, from: Data(contentsOf: file))
                drafts[draft.id] = draft
            } catch { warnings.append("一份草稿无法读取，原文件已保留。") }
        }
        self.records = loaded; self.draftRecords = drafts; self.loadWarnings = warnings
    }

    public func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(documents: records.values.sorted { $0.createdAt > $1.createdAt }, folders: catalog.folders, preferences: catalog.preferences, drafts: draftRecords.values.sorted { $0.updatedAt > $1.updatedAt }, loadWarnings: loadWarnings)
    }

    @discardableResult
    public func createText(title: String, body: String, folderID: UUID? = nil, language: String = "ja-JP") throws -> ReaderDocument {
        try validateBody(body); try validateFolder(folderID)
        let document = ReaderDocument(title: Self.title(title, fallback: body), text: body, language: language, folderID: folderID)
        try commit(document)
        return document
    }

    @discardableResult
    public func updateText(id: UUID, title: String, body: String) throws -> ReaderDocument {
        try validateBody(body)
        var document = try activeDocument(id)
        guard document.kind != .pdf else { throw RepositoryError.unsupportedFile }
        document.title = Self.title(title, fallback: body)
        if document.text != body {
            document.text = body; document.contentRevision += 1; document.position = ReadingPosition()
            let paragraphs = document.paragraphs
            document.bookmarks = document.bookmarks.map { bookmark in
                var result = bookmark
                if let index = paragraphs.firstIndex(where: { $0.hasPrefix(bookmark.excerpt) }) {
                    result.paragraphIndex = index; result.isOrphaned = false
                } else { result.isOrphaned = true }
                return result
            }
        }
        document.modifiedAt = Date(); try commit(document)
        return document
    }

    @discardableResult
    public func importDocument(sourceURL: URL, text: String, kind: DocumentKind, pageTexts: [String] = [], allowDuplicate: Bool = false, folderID: UUID? = nil, language: String = "ja-JP") throws -> ReaderDocument {
        try validateFolder(folderID)
        let ext = sourceURL.pathExtension.lowercased()
        guard (kind == .pdf && ext == "pdf") || (kind == .txt && ext == "txt") || (kind == .markdown && ext == "md") else { throw RepositoryError.unsupportedFile }
        guard pageTexts.count <= 1000 else { throw RepositoryError.tooManyPages }
        if kind == .pdf {
            guard text.count <= 10_000_000 else { throw RepositoryError.textTooLong }
        } else { try validateBody(text) }
        let size = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 200 * 1024 * 1024 else { throw RepositoryError.fileTooLarge }
        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard data.count <= 200 * 1024 * 1024 else { throw RepositoryError.fileTooLarge }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if !allowDuplicate, let existing = records.values.first(where: { $0.deletedAt == nil && $0.sourceFingerprint == digest }) {
            throw RepositoryError.duplicate(existing.id)
        }
        var document = ReaderDocument(title: Self.title(sourceURL.deletingPathExtension().lastPathComponent, fallback: text), text: text, kind: kind, language: language, folderID: folderID)
        document.originalFilename = sourceURL.lastPathComponent
        document.originalRelativePath = "Documents/\(document.id.uuidString)/original.\(ext)"
        document.sourceFingerprint = digest; document.pageTexts = pageTexts
        let directory = documentDirectory(document.id)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("original.\(ext)"), options: .atomic)
            try commit(document)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        return document
    }

    public func rename(id: UUID, title: String) throws {
        var document = try activeDocument(id)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RepositoryError.invalidName }
        document.title = String(name.prefix(200)); document.modifiedAt = Date(); try commit(document)
    }

    public func toggleFavorite(id: UUID) throws {
        var document = try activeDocument(id); document.isFavorite.toggle(); try commit(document)
    }

    public func move(ids: [UUID], folderID: UUID?) throws {
        try validateFolder(folderID)
        let documents = try ids.map { try activeDocument($0) }
        for var document in documents { document.folderID = folderID; try commit(document) }
    }

    public func trash(ids: [UUID], now: Date = Date()) throws {
        let documents = try ids.map { try activeDocument($0) }
        for var document in documents { document.deletedAt = now; try commit(document) }
    }

    public func restore(ids: [UUID]) throws {
        let documents = try ids.map { id -> ReaderDocument in
            guard let document = records[id], document.deletedAt != nil else { throw RepositoryError.missingDocument }; return document
        }
        for var document in documents {
            document.deletedAt = nil
            if let folder = document.folderID, !catalog.folders.contains(where: { $0.id == folder }) { document.folderID = nil }
            try commit(document)
        }
    }

    public func deletePermanently(ids: [UUID]) throws {
        // Missing IDs are already deleted, so retrying a partially completed batch is safe.
        for id in ids { if let record = records[id], record.deletedAt == nil { throw RepositoryError.notInTrash } }
        for id in ids where records[id] != nil {
            let directory = documentDirectory(id)
            if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
            records.removeValue(forKey: id)
            let relatedDrafts = draftRecords.values.filter { $0.documentID == id }.map(\.id)
            for draftID in relatedDrafts { try removeDraft(id: draftID) }
        }
    }

    public func purgeExpiredTrash(now: Date = Date()) throws {
        let expired = records.values.filter { document in
            guard let deletedAt = document.deletedAt else { return false }
            return now.timeIntervalSince(deletedAt) >= 30 * 86400
        }.map(\.id)
        try deletePermanently(ids: expired)
    }

    @discardableResult
    public func addFolder(name: String) throws -> ReaderFolder {
        let name = try validatedFolderName(name)
        let folder = ReaderFolder(name: name); var next = catalog; next.folders.append(folder)
        try saveCatalog(next); catalog = next
        return folder
    }

    public func renameFolder(id: UUID, name: String) throws {
        let name = try validatedFolderName(name, excluding: id)
        guard let index = catalog.folders.firstIndex(where: { $0.id == id }) else { throw RepositoryError.invalidFolder }
        var next = catalog; next.folders[index].name = name; try saveCatalog(next); catalog = next
    }

    public func deleteFolder(id: UUID) throws {
        guard catalog.folders.contains(where: { $0.id == id }) else { throw RepositoryError.invalidFolder }
        for var document in records.values.filter({ $0.folderID == id }) { document.folderID = nil; try commit(document) }
        var next = catalog; next.folders.removeAll { $0.id == id }; try saveCatalog(next); catalog = next
    }

    public func recordOpened(id: UUID) throws {
        var document = try activeDocument(id); document.lastOpenedAt = Date(); try commit(document)
    }

    public func setPosition(id: UUID, position: ReadingPosition) throws {
        var document = try activeDocument(id)
        document.position = ReadingPosition(
            paragraphIndex: min(max(0, position.paragraphIndex), max(0, document.paragraphs.count - 1)),
            pageIndex: min(max(0, position.pageIndex), max(0, document.pageTexts.count - 1)),
            progress: position.progress.isFinite ? min(max(position.progress, 0), 1) : 0
        )
        try commit(document)
    }

    public func addBookmark(id: UUID, paragraphIndex: Int, pageIndex: Int? = nil) throws {
        var document = try activeDocument(id)
        let excerpt: String
        if let pageIndex {
            guard document.pageTexts.indices.contains(pageIndex) else { throw RepositoryError.missingDocument }
            excerpt = String(document.pageTexts[pageIndex].trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        } else {
            guard document.paragraphs.indices.contains(paragraphIndex) else { throw RepositoryError.missingDocument }
            excerpt = String(document.paragraphs[paragraphIndex].prefix(120))
        }
        guard !document.bookmarks.contains(where: { !$0.isOrphaned && $0.paragraphIndex == paragraphIndex && $0.pageIndex == pageIndex }) else { return }
        document.bookmarks.append(ReaderBookmark(paragraphIndex: paragraphIndex, pageIndex: pageIndex, excerpt: excerpt))
        try commit(document)
    }

    public func removeBookmark(documentID: UUID, bookmarkID: UUID) throws {
        var document = try activeDocument(documentID); document.bookmarks.removeAll { $0.id == bookmarkID }; try commit(document)
    }

    public func setPreferences(_ preferences: ReaderPreferences) throws {
        var next = catalog; next.preferences = preferences
        next.preferences.fontSize = preferences.fontSize.isFinite ? min(max(preferences.fontSize, 17), 30) : 20
        next.preferences.lineSpacing = preferences.lineSpacing.isFinite ? min(max(preferences.lineSpacing, 0), 24) : 10
        next.preferences.defaultRate = Self.rate(preferences.defaultRate)
        try saveCatalog(next); catalog = next
    }

    public func setDocumentRate(id: UUID, rate: Double?) throws {
        var document = try activeDocument(id); document.playbackRate = rate.map(Self.rate); try commit(document)
    }

    public func saveDraft(_ draft: EditorDraft) throws {
        guard draft.body.count <= 10_000_000 else { throw RepositoryError.textTooLong }
        try Self.encode(draft).write(to: draftURL(draft.id), options: .atomic); draftRecords[draft.id] = draft
    }

    public func removeDraft(id: UUID) throws {
        let url = draftURL(id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        draftRecords.removeValue(forKey: id)
    }

    public func originalURL(for id: UUID) throws -> URL {
        let document = try activeDocument(id)
        guard let relative = document.originalRelativePath else { throw RepositoryError.missingDocument }
        let expected = documentDirectory(id).standardizedFileURL
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.deletingLastPathComponent() == expected, fileManager.fileExists(atPath: url.path) else { throw RepositoryError.missingDocument }
        return url
    }

    public func exportTextURL(for id: UUID) throws -> URL {
        let document = try activeDocument(id)
        let directory = root.appendingPathComponent("Caches/Exports/\(id.uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = String(document.title.prefix(80)).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let url = directory.appendingPathComponent(safeName + ".txt")
        try Data(document.text.utf8).write(to: url, options: .atomic)
        return url
    }

    public func storageUsage() throws -> StorageUsage {
        StorageUsage(documents: try directorySize(root.appendingPathComponent("Documents")) + Int64((try? root.appendingPathComponent("library.json").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), drafts: try directorySize(root.appendingPathComponent("Drafts")), caches: try directorySize(root.appendingPathComponent("Caches")))
    }

    public func clearCaches() throws {
        let directory = root.appendingPathComponent("Caches")
        try fileManager.removeItem(at: directory); try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func resetLibrary() throws {
        let parent = root.deletingLastPathComponent()
        let backup = parent.appendingPathComponent("\(root.lastPathComponent)-reset-old-\(UUID())")
        let replacement = parent.appendingPathComponent("\(root.lastPathComponent)-reset-new-\(UUID())")
        let marker = Self.resetMarker(for: root)
        // Finish every allocation and write before moving the user's original directory.
        do {
            for name in ["Documents", "Drafts", "Caches"] { try fileManager.createDirectory(at: replacement.appendingPathComponent(name), withIntermediateDirectories: true) }
            try Self.encode(Catalog()).write(to: replacement.appendingPathComponent("library.json"), options: .atomic)
            try Self.encode(["backup": backup.lastPathComponent]).write(to: marker, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: replacement)
            throw error
        }
        do {
            try fileManager.moveItem(at: root, to: backup)
            do { try fileManager.moveItem(at: replacement, to: root) }
            catch {
                do { try fileManager.moveItem(at: backup, to: root) }
                catch {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "重置未完成，原资料仍保留在 \(backup.path)。重启应用会尝试恢复，请勿删除该目录。"])
                }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: replacement)
            if fileManager.fileExists(atPath: root.path), !fileManager.fileExists(atPath: backup.path) { try? fileManager.removeItem(at: marker) }
            throw error
        }
        records = [:]; draftRecords = [:]; catalog = Catalog(); loadWarnings = []
        do {
            try fileManager.removeItem(at: backup)
            try fileManager.removeItem(at: marker)
        } catch {
            loadWarnings = ["资料库已清空，旧备份尚未清理。下次启动会继续清理：\(backup.path)"]
        }
    }

    private static func resetMarker(for root: URL) -> URL {
        root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent).reset-recovery.json")
    }

    private static func recoverInterruptedReset(root: URL, fileManager: FileManager) throws {
        let marker = resetMarker(for: root)
        guard fileManager.fileExists(atPath: marker.path) else { return }
        let record = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: marker))
        guard let name = record["backup"], name.hasPrefix("\(root.lastPathComponent)-reset-old-"), !name.contains("/"), !name.contains("..") else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "资料库恢复记录损坏，现有文件未被改动。"])
        }
        let backup = root.deletingLastPathComponent().appendingPathComponent(name)
        if !fileManager.fileExists(atPath: root.path) {
            guard fileManager.fileExists(atPath: backup.path) else { throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "找不到待恢复的资料库，请保留现有文件并从设备备份恢复。"])}
            try fileManager.moveItem(at: backup, to: root)
        } else if fileManager.fileExists(atPath: backup.path) {
            // A replacement at the original path means the explicitly confirmed reset committed.
            try fileManager.removeItem(at: backup)
        }
        try fileManager.removeItem(at: marker)
    }

    private func activeDocument(_ id: UUID) throws -> ReaderDocument {
        guard let document = records[id], document.deletedAt == nil else { throw RepositoryError.missingDocument }; return document
    }
    private func validateBody(_ body: String) throws {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RepositoryError.emptyText }
        guard body.count <= 10_000_000 else { throw RepositoryError.textTooLong }
    }
    private func validateFolder(_ id: UUID?) throws {
        if let id, !catalog.folders.contains(where: { $0.id == id }) { throw RepositoryError.invalidFolder }
    }
    private func validatedFolderName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !name.contains("/"), !name.contains(":"), !catalog.folders.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { throw RepositoryError.invalidName }
        return name
    }
    private func documentDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Documents/\(id.uuidString)") }
    private func draftURL(_ id: UUID) -> URL { root.appendingPathComponent("Drafts/\(id.uuidString).json") }
    private func commit(_ document: ReaderDocument) throws {
        let directory = documentDirectory(document.id)
        if !fileManager.fileExists(atPath: directory.path) { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        try Self.encode(document).write(to: directory.appendingPathComponent("document.json"), options: .atomic)
        records[document.id] = document
    }
    private func saveCatalog(_ next: Catalog) throws { try Self.encode(next).write(to: root.appendingPathComponent("library.json"), options: .atomic) }
    private static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private static func title(_ title: String, fallback: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return String(name.prefix(200)) }
        return String((fallback.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "未命名文本").trimmingCharacters(in: .whitespaces).prefix(40))
    }
    private static func rate(_ value: Double) -> Double { value.isFinite ? min(max(value, 0.5), 2) : 1 }
    private func directorySize(_ directory: URL) throws -> Int64 {
        guard let files = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
}
