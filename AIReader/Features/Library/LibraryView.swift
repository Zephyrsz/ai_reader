import SwiftUI
import ReaderCore

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .recentlyOpened
    @State private var folderID: UUID?
    @State private var selected = Set<UUID>()
    @State private var batchMode = false
    @State private var showingFolderName = false
    @State private var folderName = ""
    @State private var editingFolder: ReaderFolder?
    @State private var confirmingDelete = false
    @State private var pendingPermanentDelete: ReaderDocument?
    @State private var renamingDocument: ReaderDocument?
    @State private var documentName = ""
    @State private var showingDrafts = false

    private var visible: [ReaderDocument] {
        LibraryQuery.apply(documents: store.snapshot.documents, search: search, filter: filter, sort: sort, folderID: folderID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if batchMode { batchToolbar }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !store.snapshot.loadWarnings.isEmpty {
                        Label("部分资料无法读取，原文件已保留。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Color(uiColor: .systemOrange)).frame(maxWidth: .infinity, alignment: .leading).readerCard()
                    }
                    searchBox
                    if let folderID, let folder = store.snapshot.folders.first(where: { $0.id == folderID }) {
                        Button { self.folderID = nil } label: { Label("全部资料  /  \(folder.name)", systemImage: "chevron.left").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.accessibilityIdentifier("library.backToAll")
                    }
                    filterPicker
                    if folderID == nil { folderSection }
                    HStack {
                        Text(folderID.flatMap { id in store.snapshot.folders.first { $0.id == id }?.name } ?? "全部资料")
                            .font(.headline).foregroundStyle(AppTheme.text)
                        Spacer()
                        Picker("排序", selection: $sort) {
                            ForEach(LibrarySort.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.menu).font(.caption).accessibilityIdentifier("library.sort")
                    }
                    if visible.isEmpty { emptyResults }
                    else {
                        LazyVStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(visible) { document in documentCell(document) }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, AppTheme.Spacing.md).padding(.bottom, AppTheme.Spacing.lg)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .task { await store.refresh() }
        .alert(editingFolder == nil ? "新建文件夹" : "重命名文件夹", isPresented: $showingFolderName) {
            TextField("文件夹名称", text: $folderName)
            Button("取消", role: .cancel) { editingFolder = nil }
            Button("保存") {
                let name = folderName
                Task {
                    if let folder = editingFolder { _ = await store.perform { try await $0.renameFolder(id: folder.id, name: name) } }
                    else { _ = await store.perform { _ = try await $0.addFolder(name: name) } }
                    editingFolder = nil
                }
            }
        } message: { Text("文件夹仅支持一层结构。") }
        .alert("重命名资料", isPresented: Binding(get: { renamingDocument != nil }, set: { if !$0 { renamingDocument = nil } })) {
            TextField("资料名称", text: $documentName)
            Button("取消", role: .cancel) { renamingDocument = nil }
            Button("保存") {
                guard let document = renamingDocument else { return }
                let name = documentName
                Task { _ = await store.perform { try await $0.rename(id: document.id, title: name) }; renamingDocument = nil }
            }
        }
        .sheet(isPresented: $showingDrafts) { DraftsView() }
        .confirmationDialog("删除所选资料？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("移入最近删除", role: .destructive) { Task { if await store.perform({ try await $0.trash(ids: Array(selected)) }) { selected.removeAll(); batchMode = false } } }
            Button("取消", role: .cancel) {}
        } message: { Text("资料将保留 30 天，可在最近删除中恢复。") }
        .confirmationDialog("永久删除此资料？", isPresented: Binding(get: { pendingPermanentDelete != nil }, set: { if !$0 { pendingPermanentDelete = nil } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) {
                guard let document = pendingPermanentDelete else { return }
                Task { _ = await store.perform { try await $0.deletePermanently(ids: [document.id]) }; pendingPermanentDelete = nil }
            }
            Button("取消", role: .cancel) { pendingPermanentDelete = nil }
        } message: { Text("此操作无法撤销。") }
    }

    private var header: some View {
        HStack {
            Text("文件库").font(.largeTitle.bold()).foregroundStyle(AppTheme.text).accessibilityIdentifier("library")
            Spacer()
            NavigationLink { TrashView() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("最近删除")
            Button { store.newText() } label: { Image(systemName: "plus").font(.system(size: AppTheme.IconSize.small, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(AppTheme.primaryButton, in: Circle()) }
                .accessibilityLabel("新建文本").accessibilityIdentifier("library.add")
            Menu {
                Button("新建文件夹", systemImage: "folder.badge.plus") { editingFolder = nil; folderName = ""; showingFolderName = true }
                Button("导入文件", systemImage: "square.and.arrow.down") { store.showFileImporter = true }
                Button("草稿", systemImage: "doc.text") { showingDrafts = true }
                Button(batchMode ? "完成选择" : "批量选择", systemImage: "checkmark.circle") { batchMode.toggle(); selected.removeAll() }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("更多操作")
        }.padding(.horizontal, 20).padding(.top, 8)
    }

    private var batchToolbar: some View {
        HStack {
            Text("已选 \(selected.count) 项").font(.subheadline.weight(.semibold))
            Spacer()
            Menu("移动") {
                Button("未分类") { runBatch { try await $0.move(ids: Array(selected), folderID: nil) } }
                ForEach(store.snapshot.folders) { folder in Button(folder.name) { runBatch { try await $0.move(ids: Array(selected), folderID: folder.id) } } }
            }.disabled(selected.isEmpty)
            Button { runBatch { repo in for id in selected where store.document(id)?.isFavorite == false { try await repo.toggleFavorite(id: id) } } } label: { Image(systemName: "star") }.disabled(selected.isEmpty).accessibilityLabel("收藏所选")
            Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }.disabled(selected.isEmpty).accessibilityLabel("删除所选")
        }.padding(.horizontal, 20).padding(.vertical, AppTheme.Spacing.sm).background(AppTheme.surface)
    }

    private var searchBox: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
            TextField("搜索标题或正文", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("library.search")
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.secondaryText) }.accessibilityLabel("清除搜索") }
        }.padding(.horizontal, AppTheme.Spacing.md).frame(minHeight: 48).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)).overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button).stroke(AppTheme.secondarySurface, lineWidth: 1))
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(LibraryFilter.allCases, id: \.self) { value in
                    Button { filter = value } label: {
                        Text(value.label).font(.subheadline.weight(.medium)).foregroundStyle(filter == value ? AppTheme.accent : AppTheme.secondaryText)
                            .padding(.horizontal, AppTheme.Spacing.md).frame(minHeight: 40).background(filter == value ? AppTheme.accent.opacity(0.12) : AppTheme.surface, in: Capsule())
                    }.accessibilityAddTraits(filter == value ? .isSelected : []).accessibilityIdentifier("library.filter.\(value.rawValue)")
                }
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text("文件夹").font(.headline).foregroundStyle(AppTheme.text)
                Spacer()
                Button("管理") { editingFolder = nil; folderName = ""; showingFolderName = true }
                    .font(.subheadline).accessibilityIdentifier("library.manageFolders")
            }
            if store.snapshot.folders.isEmpty {
                Button { editingFolder = nil; folderName = ""; showingFolderName = true } label: { Label("新建文件夹", systemImage: "folder.badge.plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: 54).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)) }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.xs) {
                    ForEach(store.snapshot.folders) { folder in
                        Button { folderID = folder.id } label: {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                HStack { Image(systemName: "folder.fill").foregroundStyle(AppTheme.accent); Spacer(); Menu {
                                    Button("重命名", systemImage: "pencil") { editingFolder = folder; folderName = folder.name; showingFolderName = true }
                                    Button("删除文件夹", systemImage: "trash", role: .destructive) { Task { _ = await store.perform { try await $0.deleteFolder(id: folder.id) } } }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("管理\(folder.name)") }
                                Text(folder.name).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(store.documents.filter { $0.folderID == folder.id }.count) 篇资料").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.foregroundStyle(AppTheme.text).padding(AppTheme.Spacing.md).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card))
                        }.buttonStyle(.plain).accessibilityIdentifier("library.folder.\(folder.id)")
                    }
                }
            }
        }
    }

    private func documentCell(_ document: ReaderDocument) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if batchMode {
                Image(systemName: selected.contains(document.id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selected.contains(document.id) ? AppTheme.accent : AppTheme.secondaryText)
            }
            Button {
                if batchMode { if selected.contains(document.id) { selected.remove(document.id) } else { selected.insert(document.id) } }
                else { store.openDocument(document.id) }
            } label: { DocumentRow(document: document).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            if !batchMode {
                Menu {
                    Button(document.isFavorite ? "取消收藏" : "收藏", systemImage: "star") { Task { _ = await store.perform { try await $0.toggleFavorite(id: document.id) } } }
                    Menu("移动到") {
                        Button("未分类") { Task { _ = await store.perform { try await $0.move(ids: [document.id], folderID: nil) } } }
                        ForEach(store.snapshot.folders) { folder in Button(folder.name) { Task { _ = await store.perform { try await $0.move(ids: [document.id], folderID: folder.id) } } } }
                    }
                    Button("重命名", systemImage: "pencil") { renamingDocument = document; documentName = document.title }
                    Button("移入最近删除", systemImage: "trash", role: .destructive) { Task { _ = await store.perform { try await $0.trash(ids: [document.id]) } } }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("\(document.title) 操作")
            }
        }.padding(AppTheme.Spacing.sm).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card)).overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card).stroke(AppTheme.secondarySurface, lineWidth: 0.7))
    }

    private var emptyResults: some View {
        ContentUnavailableView(search.isEmpty ? "这里还没有资料" : "没有匹配的资料", systemImage: search.isEmpty ? "doc.text" : "magnifyingglass", description: Text(search.isEmpty ? "导入文件或创建一段文本。" : "试试其他关键词，或清除筛选条件。"))
            .frame(maxWidth: .infinity).padding(.top, 20)
    }

    private func runBatch(_ operation: @escaping (LibraryRepository) async throws -> Void) {
        Task { if await store.perform(operation) { selected.removeAll(); batchMode = false } }
    }
}

struct TrashView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var permanentIDs: [UUID] = []
    private var trashed: [ReaderDocument] { store.snapshot.documents.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("返回").accessibilityIdentifier("trash.back")
                Text("最近删除").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 4)
            List {
            if trashed.isEmpty {
                ContentUnavailableView("最近删除为空", systemImage: "trash", description: Text("移入最近删除的资料会保留 30 天。"))
            } else {
                ForEach(trashed) { document in
                    VStack(alignment: .leading, spacing: 10) {
                        DocumentRow(document: document)
                        HStack {
                            Text("删除于 \((document.deletedAt ?? .now).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Button("恢复") { Task { _ = await store.perform { try await $0.restore(ids: [document.id]) } } }
                                .buttonStyle(.borderless).accessibilityIdentifier("trash.restore.\(document.id)")
                            Button("永久删除", role: .destructive) { permanentIDs = [document.id] }
                                .buttonStyle(.borderless).accessibilityIdentifier("trash.delete.\(document.id)")
                        }
                    }.padding(.vertical, 5)
                }
            }
        }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(AppTheme.background)
        .task { await store.refresh() }
        .confirmationDialog("永久删除这份资料？", isPresented: Binding(get: { !permanentIDs.isEmpty }, set: { if !$0 { permanentIDs = [] } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { let ids = permanentIDs; Task { _ = await store.perform { try await $0.deletePermanently(ids: ids) }; permanentIDs = [] } }
            Button("取消", role: .cancel) { permanentIDs = [] }
        } message: { Text("永久删除后，原文件和阅读进度都无法恢复。") }
    }
}

private struct DraftsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draftToDelete: EditorDraft?

    var body: some View {
        NavigationStack {
            List {
                if store.snapshot.drafts.isEmpty {
                    ContentUnavailableView("没有草稿", systemImage: "doc.text", description: Text("未完成的编辑会保存在这里。"))
                } else {
                    ForEach(store.snapshot.drafts) { draft in
                        NavigationLink { EditorView(draft: draft) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title.isEmpty ? "未命名草稿" : draft.title).font(.headline)
                                Text(draft.body.prefix(80)).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
                                Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(AppTheme.secondaryText)
                            }.padding(.vertical, 4)
                        }
                        .swipeActions { Button("删除", systemImage: "trash", role: .destructive) { draftToDelete = draft } }
                        .accessibilityIdentifier("draft.\(draft.id)")
                    }
                }
            }
            .navigationTitle("本机草稿").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("删除这份草稿？", isPresented: Binding(get: { draftToDelete != nil }, set: { if !$0 { draftToDelete = nil } }), titleVisibility: .visible) {
                Button("删除草稿", role: .destructive) {
                    guard let draft = draftToDelete else { return }
                    Task { _ = await store.perform { try await $0.removeDraft(id: draft.id) }; draftToDelete = nil }
                }
                Button("取消", role: .cancel) { draftToDelete = nil }
            }
        }
    }
}
