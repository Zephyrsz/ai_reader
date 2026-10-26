import SwiftUI
import PDFKit
import ReaderCore

private enum ReaderMode: String, CaseIterable, Identifiable {
    case text = "文本", original = "原文"
    var id: String { rawValue }
}

@MainActor
struct ReaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var bodyScale = 1.0
    let documentID: UUID
    @State private var mode: ReaderMode = .text
    @State private var query = ""
    @State private var matchCount = 0
    @State private var showingFind = false
    @State private var showingBookmarks = false
    @State private var showingAppearance = false
    @State private var showingSpeed = false
    @State private var showingVoiceSettings = false
    @State private var showingRename = false
    @State private var showingPDFUnlock = false
    @State private var pdfPassword = ""
    @State private var pdfUnlockError: String?
    @State private var renameText = ""
    @State private var pdfPage = 0
    @State private var textProgress = 0.0
    @State private var saveTask: Task<Void, Never>?
    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var originalURL: URL?
    @State private var exportedTextURL: URL?

    private var document: ReaderDocument? { store.document(documentID) }
    private var isPDF: Bool { document?.kind == .pdf }

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    header(document)
                    if isPDF { Picker("阅读模式", selection: $mode) { ForEach(ReaderMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 10) }
                    if showingFind { findBar(document) }
                    if isPDF && mode == .original { pdfContent(document) }
                    else { textContent(document) }
                    speechPlayer(document)
                }
                .background(AppTheme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .toolbar(.hidden, for: .navigationBar)
                .task(id: document.contentRevision) { await loadDocument(document) }
                .onChange(of: textProgress) { _, value in savePosition(progress: value) }
                .onChange(of: pdfPage) { _, value in savePosition(page: value) }
                .onDisappear { saveNow() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { saveNow() } }
                .sheet(isPresented: $showingSpeed) { SpeedSheet(documentID: documentID) }
                .sheet(isPresented: $showingVoiceSettings) {
                    NavigationStack { VoiceSettingsView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showingVoiceSettings = false } } } }
                }
                .sheet(isPresented: $showingAppearance) {
                    NavigationStack { ReadingAppearanceSheet().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showingAppearance = false } } } }
                }
                .sheet(isPresented: $showingBookmarks) { bookmarkSheet(document) }
                .alert("重命名", isPresented: $showingRename) {
                    TextField("名称", text: $renameText)
                    Button("取消", role: .cancel) {}
                    Button("保存") { Task { await renameDocument() } }
                }
                .alert("解锁 PDF", isPresented: $showingPDFUnlock) {
                    SecureField("PDF 密码", text: $pdfPassword)
                    Button("取消", role: .cancel) {}
                    Button("解锁") { unlockPDF() }
                } message: { Text(pdfUnlockError ?? "密码只在本次阅读期间使用。") }
            } else {
                ContentUnavailableView("资料不存在", systemImage: "doc.questionmark")
            }
        }
    }

    private func header(_ document: ReaderDocument) -> some View {
        HStack(spacing: 8) {
            Button { saveNow(); dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("返回").accessibilityIdentifier("reader.back")
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).font(.headline).lineLimit(1)
                Text("\(document.kind.label) · \(document.language)").font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 4)
            Button { showingFind.toggle() } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel("查找").accessibilityIdentifier("reader.find")
            Button { showingAppearance = true } label: { Image(systemName: "textformat.size").frame(width: 44, height: 44) }.accessibilityLabel("阅读设置").accessibilityIdentifier("reader.appearance")
            Menu {
                Button("目录与书签", systemImage: "list.bullet") { showingBookmarks = true }
                Button("添加书签", systemImage: "bookmark") { Task { await addBookmark(document) } }
                Button("编辑文本", systemImage: "pencil") { store.editDocument(document) }
                    .disabled(document.kind == .pdf)
                if document.kind == .pdf { Button("保存文本副本并编辑", systemImage: "doc.on.doc") { store.newText(body: document.text) } }
                Button(document.isFavorite ? "取消收藏" : "收藏", systemImage: "star") { Task { await toggleFavorite() } }
                Button("重命名", systemImage: "pencil.line") { renameText = document.title; showingRename = true }
                if let originalURL { ShareLink(item: originalURL, preview: SharePreview(document.title)) { Label("分享原文件", systemImage: "square.and.arrow.up") } }
                if let exportedTextURL { ShareLink(item: exportedTextURL, preview: SharePreview("\(document.title).txt")) { Label("分享 TXT 文本", systemImage: "text.alignleft") } }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 12).padding(.top, 4)
    }

    private func textContent(_ document: ReaderDocument) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isPDF {
                        HStack {
                            Text("第 \(min(pdfPage + 1, max(document.pageTexts.count, 1))) / \(max(document.pageTexts.count, 1)) 页").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Button("目录 / 页面") { showingBookmarks = true }.font(.subheadline)
                        }
                    }
                    if document.text.isEmpty { ContentUnavailableView("没有可提取的文字", systemImage: "doc.text.magnifyingglass", description: Text("此 PDF 仍可在原文模式查看。扫描页不提供本地 OCR。")) }
                    else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                Text(highlightedParagraph(paragraph, index: index, document: document))
                                    .font(.system(size: CGFloat(store.preferences.fontSize) * bodyScale, weight: .regular, design: .serif))
                                    .lineSpacing(CGFloat(store.preferences.lineSpacing))
                                    .foregroundStyle(AppTheme.text)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier(index == 0 ? "reader.text" : "reader.paragraph.\(index)")
                                    .background(ParagraphFrameReporter(index: index))
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(GeometryReader { geometry in Color.clear.preference(key: ContentMetricsKey.self, value: ContentMetrics(top: geometry.frame(in: .named("readerScroll")).minY, height: geometry.size.height)) })
                    }
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
            }
            .coordinateSpace(name: "readerScroll")
            .background(GeometryReader { geometry in Color.clear.preference(key: ViewportHeightKey.self, value: geometry.size.height) })
            .onPreferenceChange(ContentMetricsKey.self) { metrics in
                if metrics.height <= visibleHeight { textProgress = 1 }
                else { textProgress = min(max(-metrics.top / (metrics.height - visibleHeight), 0), 1) }
            }
            .onPreferenceChange(ParagraphFramesKey.self) { frames in
                guard let firstVisible = frames.filter({ $0.value <= 0 }).max(by: { $0.value < $1.value })?.key
                        ?? frames.min(by: { $0.value < $1.value })?.key else { return }
                currentParagraph = firstVisible
            }
            .onPreferenceChange(ViewportHeightKey.self) { height in
                visibleHeight = height
            }
            .onAppear {
                let index = document.position.paragraphIndex
                DispatchQueue.main.async { proxy.scrollTo(index, anchor: .top); currentParagraph = index }
            }
            .overlay(alignment: .bottomTrailing) {
                if !document.bookmarks.isEmpty { Button { showingBookmarks = true } label: { Image(systemName: "bookmark.fill").padding(12).background(AppTheme.surface, in: Circle()) }.padding(16).accessibilityLabel("书签与目录") }
            }
            .onChange(of: query) { _, value in
                guard !value.isEmpty, let paragraph = document.paragraphs.firstIndex(where: { $0.range(of: value, options: .caseInsensitive) != nil }) else { return }
                withAnimation { proxy.scrollTo(paragraph, anchor: .top) }
            }
            .onChange(of: store.playback.paragraphIndex) { _, index in
                guard store.preferences.followSpeech, store.playback.documentID == document.id else { return }
                withAnimation { proxy.scrollTo(index, anchor: .top) }
                currentParagraph = index
            }
            .onChange(of: targetParagraph) { _, index in
                guard let index else { return }
                withAnimation { proxy.scrollTo(index, anchor: .top) }
                targetParagraph = nil
            }
        }
    }

    @State private var visibleHeight: CGFloat = 500
    @State private var currentParagraph = 0

    private func highlightedParagraph(_ paragraph: String, index: Int, document: ReaderDocument) -> AttributedString {
        var text = AttributedString(paragraph)
        guard store.preferences.followSpeech, store.playback.documentID == document.id,
              let sentence = store.playback.highlightedSentence, sentence.paragraphIndex == index,
              sentence.sentenceRange.upperBound <= text.characters.count else { return text }
        let start = text.characters.index(text.startIndex, offsetBy: sentence.sentenceRange.lowerBound)
        let end = text.characters.index(text.startIndex, offsetBy: sentence.sentenceRange.upperBound)
        text[start..<end][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = AppTheme.accent.opacity(0.18)
        return text
    }

    private func pdfContent(_ document: ReaderDocument) -> some View {
        VStack(spacing: 0) {
            if document.pageTexts.count > 0 {
                HStack {
                    Button { pdfPage = max(pdfPage - 1, 0); goToPDFPage(pdfPage) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一页")
                    TextField("页", value: Binding(get: { pdfPage + 1 }, set: { pdfPage = min(max($0 - 1, 0), document.pageTexts.count - 1); goToPDFPage(pdfPage) }), format: .number).keyboardType(.numberPad).multilineTextAlignment(.center).frame(width: 80).textFieldStyle(.roundedBorder)
                    Text("/ \(document.pageTexts.count)").foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Menu("页面") { ForEach(document.pageTexts.indices, id: \.self) { page in Button("第 \(page + 1) 页") { pdfPage = page; goToPDFPage(page) } } }
                }.padding(.horizontal, 12)
                if let pdfDocument { PDFOriginalView(document: pdfDocument, pdfView: $pdfView, pageIndex: $pdfPage) { pdfPage = $0; textProgress = Double($0 + 1) / Double(max(document.pageTexts.count, 1)) } }
                else { ProgressView("打开 PDF…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else { ContentUnavailableView("PDF 原文不可用", systemImage: "doc.richtext") }
        }
    }

    private func findBar(_ document: ReaderDocument) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("查找正文", text: $query).textInputAutocapitalization(.never).accessibilityIdentifier("reader.searchField")
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除查找") }
            if !query.isEmpty { Text(matchCount == 0 ? "无结果" : "\(matchCount) 个匹配").font(.caption).foregroundStyle(AppTheme.secondaryText) }
        }.padding(10).background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 20)
            .onChange(of: query) { _, value in updatePDFMatches(value) }
    }

    private func updatePDFMatches(_ value: String) {
        guard !value.isEmpty else { matchCount = 0; pdfView?.clearSelection(); return }
        if isPDF, let pdfDocument {
            let selections = pdfDocument.findString(value, withOptions: .caseInsensitive)
            matchCount = selections.count
            if let first = selections.first, let page = first.pages.first {
                pdfPage = pdfDocument.index(for: page)
                pdfView?.setCurrentSelection(first, animate: true); pdfView?.go(to: page)
            }
        } else if let text = document?.text {
            // Case-insensitive matches also support Latin text imported with Japanese content.
            var count = 0
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: value, options: .caseInsensitive, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<text.endIndex
            }
            matchCount = count
        }
    }

    private func goToPDFPage(_ index: Int) {
        guard let pdfDocument, pdfDocument.pageCount > index, let page = pdfDocument.page(at: index) else { return }
        pdfView?.go(to: page)
    }

    private func speechPlayer(_ document: ReaderDocument) -> some View {
        let active = store.playback.documentID == document.id
        let supported = document.language == "ja-JP" && !document.text.isEmpty
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(SpeechVoice.allCases) { voice in
                        Button {
                            Task {
                                guard store.playback.canChangeVoice else { return }
                                var preferences = store.preferences
                                preferences.voice = voice
                                await store.savePreferences(preferences)
                            }
                        } label: {
                            if store.preferences.voice == voice { Label(voice.name, systemImage: "checkmark") }
                            else { Text(voice.name) }
                        }
                        .accessibilityIdentifier("reader.voice.\(voice.rawValue)")
                    }
                    Divider()
                    Button("音色设置与试听", systemImage: "waveform") { showingVoiceSettings = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.wave.2")
                        Text(store.preferences.voice.name).lineLimit(1)
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                    .font(.caption.weight(.medium))
                    .frame(minHeight: 44)
                }
                .disabled(!store.playback.canChangeVoice)
                .accessibilityLabel("朗读音色")
                .accessibilityValue(store.preferences.voice.name)
                .accessibilityHint(store.playback.canChangeVoice ? "选择朗读音色" : "暂停或停止朗读后可切换")
                .accessibilityIdentifier("reader.voice")
                Spacer(minLength: 0)
                Text(supported ? (active ? store.playback.status : "日语 · 离线朗读") : "当前仅支持有文字的日语资料")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.trailing).lineLimit(3)
                    .accessibilityIdentifier("reader.speechStatus")
            }
            .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Color.clear.frame(width: 48, height: 44).accessibilityHidden(true)
                Button { store.playback.skip(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!active || store.playback.segmentIndex == 0).accessibilityLabel("上一句").accessibilityIdentifier("reader.previous")
                Button {
                    store.playback.toggle(document: document, paragraph: currentParagraph, voice: store.preferences.voice, rate: document.playbackRate ?? store.preferences.defaultRate)
                } label: {
                    ZStack {
                        Circle().fill(AppTheme.accent).frame(width: 52, height: 52)
                        if active && store.playback.state == .preparing { ProgressView().tint(.white) }
                        else { Image(systemName: active && store.playback.isActive ? "pause.fill" : "play.fill").foregroundStyle(.white) }
                    }
                }
                .disabled(!supported).accessibilityLabel(active && store.playback.isActive ? "暂停" : "播放")
                .accessibilityIdentifier("reader.play")
                Button { store.playback.skip(1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!active || store.playback.segmentIndex + 1 >= store.playback.segmentCount).accessibilityLabel("下一句").accessibilityIdentifier("reader.next")
                Button { showingSpeed = true } label: { Text(String(format: "%.2g×", document.playbackRate ?? store.preferences.defaultRate)).frame(minWidth: 48, minHeight: 44) }.accessibilityLabel("语速")
            }
            if active && store.playback.hasSession {
                Button("停止朗读") { store.playback.stop() }.font(.caption).frame(minHeight: 44).accessibilityIdentifier("reader.stop")
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 8).background(AppTheme.surface)
    }

    private func bookmarkSheet(_ document: ReaderDocument) -> some View {
        NavigationStack {
            List {
                if let outline = pdfDocument?.outlineRoot, outline.numberOfChildren > 0 {
                    Section("目录") {
                        ForEach(outlineEntries(outline), id: \.id) { entry in
                            Button { if let page = entry.page { pdfPage = page; goToPDFPage(page); mode = .original; showingBookmarks = false } } label: {
                                Text(entry.title).padding(.leading, CGFloat(entry.level * 16)).frame(minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                }
                if isPDF {
                    Section("页面") {
                        ForEach(document.pageTexts.indices, id: \.self) { page in
                            Button { pdfPage = page; mode = .original; showingBookmarks = false } label: {
                                HStack(spacing: 12) {
                                    if let pdfPageObject = pdfDocument?.page(at: page) { PDFPageThumbnail(page: pdfPageObject).frame(width: 52, height: 72) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("第 \(page + 1) 页").font(.subheadline.weight(.semibold))
                                        Text(document.pageTexts[page].prefix(48)).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
                                    }
                                }.frame(minHeight: 76)
                            }
                        }
                    }
                }
                Section("书签") {
                    if document.bookmarks.isEmpty { Text("尚无书签").foregroundStyle(AppTheme.secondaryText) }
                    ForEach(document.bookmarks) { bookmark in
                        Button {
                            if bookmark.isOrphaned { return }
                            if let page = bookmark.pageIndex { pdfPage = page; goToPDFPage(page); mode = .original }
                            else { targetParagraph = bookmark.paragraphIndex }
                            showingBookmarks = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(bookmark.excerpt).lineLimit(2)
                                if bookmark.isOrphaned { Text("正文已修改 · 原位置失效，摘录已保留").font(.caption).foregroundStyle(AppTheme.secondaryText) }
                                Text("\(bookmark.pageIndex.map { "第 \($0 + 1) 页 · " } ?? "")\(bookmark.createdAt.formatted(date: .numeric, time: .omitted))").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .swipeActions { Button("删除", role: .destructive) { Task { await removeBookmark(bookmark.id) } } }
                    }
                }
            }
            .navigationTitle("目录与书签")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showingBookmarks = false }.frame(minWidth: 44, minHeight: 44) } }
        }
    }

    private struct OutlineEntry { let id = UUID(); let title: String; let page: Int?; let level: Int }
    private func outlineEntries(_ root: PDFOutline) -> [OutlineEntry] {
        var result: [OutlineEntry] = []
        func visit(_ node: PDFOutline, level: Int) {
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                var pageIndex: Int?
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                if let page = destination?.page { pageIndex = pdfDocument?.index(for: page) }
                result.append(OutlineEntry(title: child.label ?? "未命名", page: pageIndex, level: level))
                visit(child, level: level + 1)
            }
        }
        visit(root, level: 0)
        return result
    }

    private func loadDocument(_ document: ReaderDocument) async {
        textProgress = document.position.progress
        pdfPage = document.position.pageIndex
        await store.perform { repository in try await repository.recordOpened(id: document.id) }
        if document.originalRelativePath != nil { originalURL = try? await store.repository.originalURL(for: document.id) }
        exportedTextURL = try? await store.repository.exportTextURL(for: document.id)
        if document.kind == .pdf, let url = try? await store.repository.originalURL(for: document.id) {
            let box = await Task.detached(priority: .userInitiated) { PDFDocumentBox(PDFDocument(url: url)) }.value
            pdfDocument = box.document
            if let pdfDocument, pdfDocument.isLocked { showingPDFUnlock = true }
            else { goToPDFPage(min(pdfPage, max((pdfDocument?.pageCount ?? 1) - 1, 0))) }
        }
    }

    private func savePosition(progress: Double? = nil, page: Int? = nil) {
        guard let document else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let position = ReadingPosition(paragraphIndex: document.paragraphs.isEmpty ? 0 : currentParagraph, pageIndex: page ?? pdfPage, progress: progress ?? textProgress)
            await store.perform { repository in try await repository.setPosition(id: document.id, position: position) }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard document != nil else { return }
        let position = ReadingPosition(paragraphIndex: currentParagraph, pageIndex: pdfPage, progress: textProgress)
        Task { @MainActor in
            await store.perform { repository in try await repository.setPosition(id: documentID, position: position) }
        }
    }
    @State private var targetParagraph: Int?
    private func addBookmark(_ document: ReaderDocument) async {
        let para = min(max(currentParagraph, 0), max(document.paragraphs.count - 1, 0))
        await store.perform { repository in try await repository.addBookmark(id: document.id, paragraphIndex: para, pageIndex: isPDF ? pdfPage : nil) }
    }
    private func toggleFavorite() async { await store.perform { repository in try await repository.toggleFavorite(id: documentID) } }
    private func renameDocument() async { await store.perform { repository in try await repository.rename(id: documentID, title: renameText) } }
    private func removeBookmark(_ id: UUID) async { await store.perform { repository in try await repository.removeBookmark(documentID: documentID, bookmarkID: id) } }
    private func unlockPDF() {
        guard let pdfDocument, pdfDocument.unlock(withPassword: pdfPassword) else { pdfUnlockError = "密码不正确，请重试。"; showingPDFUnlock = true; return }
        pdfPassword = ""; pdfUnlockError = nil; goToPDFPage(min(pdfPage, max(pdfDocument.pageCount - 1, 0)))
    }
}

private struct ContentMetrics: Equatable {
    var top: CGFloat
    var height: CGFloat
}

private struct PDFDocumentBox: @unchecked Sendable {
    let document: PDFDocument?
    init(_ document: PDFDocument?) { self.document = document }
}

private struct PDFPageThumbnail: UIViewRepresentable {
    let page: PDFPage
    func makeUIView(context: Context) -> UIImageView { let view = UIImageView(); view.contentMode = .scaleAspectFit; view.backgroundColor = .secondarySystemBackground; return view }
    func updateUIView(_ view: UIImageView, context: Context) { view.image = page.thumbnail(of: CGSize(width: 104, height: 144), for: .mediaBox) }
}
private struct ParagraphFrameReporter: View {
    let index: Int
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ParagraphFramesKey.self, value: [index: geometry.frame(in: .named("readerScroll")).minY])
        }
    }
}
private struct ContentMetricsKey: PreferenceKey {
    static var defaultValue = ContentMetrics(top: 0, height: 0)
    static func reduce(value: inout ContentMetrics, nextValue: () -> ContentMetrics) { value = nextValue() }
}
private struct ParagraphFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}
private struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct PDFOriginalView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var pdfView: PDFView?
    @Binding var pageIndex: Int
    let pageChanged: (Int) -> Void
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; view.document = document
        if let page = document.page(at: pageIndex) { view.go(to: page) }
        DispatchQueue.main.async { pdfView = view }
        context.coordinator.attach(view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if view.currentPage.map({ document.index(for: $0) }) != pageIndex, let page = document.page(at: pageIndex) { view.go(to: page) }
        if pdfView !== view { DispatchQueue.main.async { pdfView = view } }
    }
    func makeCoordinator() -> Coordinator { Coordinator(pageChanged: pageChanged) }
    final class Coordinator: NSObject {
        let pageChanged: (Int) -> Void
        init(pageChanged: @escaping (Int) -> Void) { self.pageChanged = pageChanged }
        func attach(_ view: PDFView) { NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: Notification.Name.PDFViewPageChanged, object: view) }
        @objc private func changed(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let page = view.currentPage else { return }
            pageChanged(view.document?.index(for: page) ?? 0)
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
