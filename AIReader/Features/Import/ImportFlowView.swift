import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import ReaderCore

private enum ImportStage: Equatable {
    case waiting, copying, parsing, importing, finished, failed(String), cancelled, duplicate(UUID)
}

private struct ImportItem: Identifiable {
    let id = UUID()
    let url: URL
    var stagedURL: URL?
    var text = ""
    var pageTexts: [String] = []
    var kind: DocumentKind = .text
    var stage: ImportStage = .waiting
    var encoding: TextFileEncoding?
    var password = ""
    var language = "ja-JP"
    var folderID: UUID?
    var warning: String?
    var title: String { url.deletingPathExtension().lastPathComponent }
    var fileSize: Int64 { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
}

private struct OpenDocumentRequest: Identifiable {
    let id: UUID
}

@MainActor
struct ImportFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    @State private var items: [ImportItem] = []
    @State private var openDocumentRequest: OpenDocumentRequest?
    @State private var importedIDs: [UUID: UUID] = [:]
    @State private var duplicateIDs: [UUID: UUID] = [:]
    @State private var cancelledItems: Set<UUID> = []

    private let maxBytes: Int64 = 50 * 1024 * 1024
    private let maxCharacters = 200_000
    private let maxPages = 300

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(items.indices, id: \.self) { index in itemView(index) }
                    if items.allSatisfy({ $0.stage == .finished || $0.stage == .cancelled }) {
                        Button("完成") { dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("导入文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { cancelPending(); dismiss() }.frame(minWidth: 44, minHeight: 44).disabled(items.contains { $0.stage == .importing }) } }
            .sheet(item: $openDocumentRequest) { request in ReaderView(documentID: request.id) }
            .task { initializeItems() }
            .onDisappear { cleanupStaging() }
            .interactiveDismissDisabled(items.contains { $0.stage == .importing })
        }
    }

    @ViewBuilder private func itemView(_ index: Int) -> some View {
        let item = items[index]
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: item.kind == .pdf ? "doc.richtext" : "doc.text").font(.title2).foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.url.lastPathComponent).font(.headline).lineLimit(2)
                    Text("\(item.kind.label) · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))").font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                statusView(item.stage)
            }
            if let warning = item.warning, warning != "password" { Label(warning, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(AppTheme.warning) }
            if case .failed(let message) = item.stage { Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(AppTheme.destructive) }
            if case .duplicate(let id) = item.stage {
                HStack {
                    Button("打开已有") { openDocumentRequest = OpenDocumentRequest(id: id) }.accessibilityIdentifier("import.openDuplicate")
                    Button("导入副本") { Task { await importItem(index, allowDuplicate: true) } }
                    Button("取消") { cancel(index) }
                }.buttonStyle(.bordered)
            } else if case .failed = item.stage {
                HStack {
                    if item.kind != .pdf && item.stagedURL != nil { Button("重新解析") { Task { await parseItem(index) } } }
                    Button("重试") { Task { await prepare(index) } }.buttonStyle(.borderedProminent)
                    Button("移除") { cancel(index) }.buttonStyle(.bordered)
                }
            } else if item.stage == .waiting {
                Picker("语言", selection: binding(index, \.language)) { Text("日本語").tag("ja-JP"); Text("简体中文").tag("zh-CN"); Text("English").tag("en-US") }.pickerStyle(.menu)
                Picker("文件夹", selection: binding(index, \.folderID)) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(store.snapshot.folders) { folder in Text(folder.name).tag(Optional(folder.id)) }
                }.pickerStyle(.menu)
                if item.kind != .pdf, let stagedURL = item.stagedURL {
                    Picker("文本编码", selection: binding(index, \.encoding)) {
                        Text("自动识别").tag(TextFileEncoding?.none)
                        ForEach(TextFileEncoding.allCases, id: \.self) { encoding in Text(encoding.label).tag(Optional(encoding)) }
                    }.pickerStyle(.menu)
                    Button(item.text.isEmpty ? "预览编码" : "重新解析预览") { Task { await parseItem(index) } }.buttonStyle(.bordered).accessibilityIdentifier("import.previewEncoding")
                    Text(stagedURL.lastPathComponent).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                if item.kind == .pdf && item.warning == "password" {
                    SecureField("PDF 密码（仅本次使用）", text: binding(index, \.password)).textFieldStyle(.roundedBorder).accessibilityIdentifier("import.pdfPassword")
                    Button("解锁并解析") { Task { await parseItem(index) } }.buttonStyle(.borderedProminent).accessibilityIdentifier("import.unlockPDF")
                }
                    if !item.text.isEmpty {
                    Text(item.text.prefix(4000)).font(.system(size: 15)).lineLimit(12).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
                    Button("确认导入") { Task { await importItem(index) } }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("import.confirm")
                    } else if item.kind == .pdf, item.stagedURL != nil, item.warning != "password" {
                        Button("仅导入 PDF 原文") { Task { await importItem(index) } }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                } else if item.stagedURL == nil {
                    Button("开始导入") { Task { await prepare(index) } }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                }
            } else if item.stage == .copying || item.stage == .parsing || item.stage == .importing {
                ProgressView(item.stage == .copying ? "复制到本机…" : item.stage == .importing ? "保存到资料库，完成后保留…" : "解析中…")
                Button(item.stage == .importing ? "正在保存…" : "取消此项") { cancel(index) }.buttonStyle(.bordered).disabled(item.stage == .importing)
            } else if item.stage == .finished {
                Button("打开") {
                    guard let id = importedIDs[item.id] else { return }
                    openDocumentRequest = OpenDocumentRequest(id: id)
                }.buttonStyle(.bordered).accessibilityIdentifier("import.openImported")
            }
        }
        .padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func statusView(_ stage: ImportStage) -> some View {
        switch stage {
        case .waiting: statusLabel("等待", symbol: "clock")
        case .copying: statusLabel("复制中", symbol: "doc.on.doc")
        case .parsing: statusLabel("解析中", symbol: "text.magnifyingglass")
        case .importing: statusLabel("保存中", symbol: "square.and.arrow.down")
        case .finished: statusLabel("已完成", symbol: "checkmark.circle")
        case .failed: statusLabel("失败", symbol: "exclamationmark.circle")
        case .cancelled: statusLabel("已取消", symbol: "xmark.circle")
        case .duplicate: statusLabel("重复", symbol: "doc.on.doc")
        }
    }

    private func statusLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 9).padding(.vertical, 6).background(AppTheme.secondarySurface, in: Capsule())
    }

    private func initializeItems() {
        guard items.isEmpty else { return }
        items = urls.map { url in
            var item = ImportItem(url: url)
            let ext = url.pathExtension.lowercased()
            item.kind = ext == "pdf" ? .pdf : ext == "md" ? .markdown : .txt
            if !["pdf", "txt", "md"].contains(ext) { item.stage = .failed("目前支持 PDF、TXT 和 MD 文件。") }
            return item
        }
    }

    private func prepare(_ index: Int) async {
        guard items.indices.contains(index) else { return }
        if let old = items[index].stagedURL { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()); update(index) { $0.stagedURL = nil; $0.text = ""; $0.pageTexts = [] } }
        update(index) { $0.stage = .copying; $0.warning = nil }
        let item = items[index]
        cancelledItems.remove(item.id)
        var staging: URL?
        do {
            let scoped = item.url.startAccessingSecurityScopedResource()
            defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }
            let sourceSize = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? item.fileSize
            guard sourceSize <= maxBytes else { throw RepositoryError.fileTooLarge }
            let stagingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-reader-import-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let destination = stagingDirectory.appendingPathComponent(item.url.lastPathComponent)
            staging = destination
            try FileManager.default.copyItem(at: item.url, to: destination)
            if cancelledItems.contains(item.id) { try? FileManager.default.removeItem(at: stagingDirectory); return }
            let stagedSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? sourceSize
            guard stagedSize <= maxBytes else { throw RepositoryError.fileTooLarge }
            update(index) { $0.stagedURL = destination; $0.stage = .waiting }
            await parseItem(index)
        } catch {
            if let staging { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
            guard !cancelledItems.contains(item.id) else { return }
            update(index) { $0.stage = .failed(error.localizedDescription) }
        }
    }

    private func parseItem(_ index: Int) async {
        guard items.indices.contains(index), let staged = items[index].stagedURL else { return }
        update(index) { $0.stage = .parsing; $0.warning = nil }
        let kind = items[index].kind, encoding = items[index].encoding, password = items[index].password
        do {
            let parsed = try await Task.detached(priority: .userInitiated) { () -> (String, [String], String?) in
                if kind == .pdf {
                    guard let pdf = PDFDocument(url: staged) else { throw RepositoryError.unsupportedFile }
                    guard pdf.pageCount <= 300 else { throw RepositoryError.tooManyPages }
                    if pdf.isLocked && !pdf.unlock(withPassword: password) { return ("", [], "password") }
                    let pages = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
                    let missing = pages.enumerated().filter { $0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { String($0.offset + 1) }
                    let text = pages.enumerated().compactMap { index, pageText in
                        let body = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
                        return body.isEmpty ? nil : "[第\(index + 1)页]\n\(body)"
                    }.joined(separator: "\n\n")
                    return (text, pages, missing.isEmpty ? nil : "以下页面没有可提取文字：\(missing.joined(separator: "、"))。这可能是扫描页或缺少文字层。")
                }
                let data = try Data(contentsOf: staged, options: .mappedIfSafe)
                do { return (try TextDecoder.decode(data, encoding: encoding), [], nil) }
                catch { return ("", [], "无法自动识别文本编码，请选择编码并预览。") }
            }.value
            guard !cancelledItems.contains(items[index].id), items[index].stage != .cancelled else {
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
                return
            }
            if parsed.2 == "password" { update(index) { $0.stage = .waiting; $0.warning = "password" }; return }
            guard parsed.0.count <= maxCharacters else { throw RepositoryError.textTooLong }
            if kind != .pdf && parsed.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed.2 == nil {
                throw RepositoryError.emptyText
            }
            guard !parsed.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                update(index) { $0.stage = .waiting; $0.warning = parsed.2 ?? "未提取到文字。这可能是扫描版 PDF。原文仍可导入查看。"; $0.text = ""; $0.pageTexts = parsed.1 }
                return
            }
            update(index) { $0.text = parsed.0; $0.pageTexts = parsed.1; $0.stage = .waiting; $0.warning = parsed.2 }
        } catch {
            guard !cancelledItems.contains(items[index].id), items[index].stage != .cancelled else { return }
            update(index) { $0.stage = .failed(error.localizedDescription) }
        }
    }

    private func importItem(_ index: Int, allowDuplicate: Bool = false) async {
        guard items.indices.contains(index), let staged = items[index].stagedURL else { return }
        let item = items[index]
        duplicateIDs[item.id] = nil
        update(index) { $0.stage = .importing; $0.warning = nil }
        do {
            let document = try await store.repository.importDocument(sourceURL: staged, text: item.text, kind: item.kind, pageTexts: item.pageTexts, allowDuplicate: allowDuplicate, folderID: item.folderID, language: item.language)
            importedIDs[item.id] = document.id
            update(index) { $0.stage = .finished }
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            await store.refresh()
        } catch RepositoryError.duplicate(let id) {
            duplicateIDs[item.id] = id
            update(index) { $0.stage = .duplicate(id) }
        } catch {
            update(index) { $0.stage = .failed(error.localizedDescription) }
        }
    }

    private func update(_ index: Int, _ change: (inout ImportItem) -> Void) { guard items.indices.contains(index) else { return }; change(&items[index]) }
    private func binding<Value>(_ index: Int, _ keyPath: WritableKeyPath<ImportItem, Value>) -> Binding<Value> { Binding(get: { items[index][keyPath: keyPath] }, set: { items[index][keyPath: keyPath] = $0 }) }
    private func cancel(_ index: Int) {
        let item = items[index]
        cancelledItems.insert(item.id)
        if item.stage != .parsing, item.stage != .importing, let url = item.stagedURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        update(index) { $0.stage = .cancelled }
    }
    private func cancelPending() { for index in items.indices where items[index].stage != .finished && items[index].stage != .importing && items[index].stage != .cancelled { cancel(index) } }
    private func cleanupStaging() {
        for index in items.indices where items[index].stage != .finished && items[index].stage != .importing {
            cancelledItems.insert(items[index].id)
            if items[index].stage != .parsing, let url = items[index].stagedURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        }
    }
}
