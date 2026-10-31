import SwiftUI
import UIKit
import ReaderCore

struct EditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: EditorDraft
    @State private var saveState = "编辑内容仅保存在本机。"
    @State private var saveTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var didSave = false
    @State private var undoHistory: [String] = []
    @State private var redoHistory: [String] = []
    @State private var applyingHistory = false
    @State private var confirmingClear = false
    @FocusState private var bodyFocused: Bool

    init(draft: EditorDraft) { _draft = State(initialValue: draft) }
    private var canSave: Bool { !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            ScrollView {
                editorContent
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(draft.documentID == nil ? "新建文本" : "编辑文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { finishAndDismiss() }.accessibilityIdentifier("editor.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { saveDocument() }.disabled(!canSave).accessibilityIdentifier("saveText") }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Button("粘贴") { pasteFromClipboard() }
                    Spacer(minLength: AppTheme.Spacing.xs)
                    Button("撤销") { undoBody() }.disabled(undoHistory.isEmpty).accessibilityIdentifier("editor.undo")
                    Button("重做") { redoBody() }.disabled(redoHistory.isEmpty).accessibilityIdentifier("editor.redo")
                    Button("收起键盘") { bodyFocused = false }
                }
                .font(.subheadline).frame(minHeight: 44).padding(.horizontal, 20)
                .background(AppTheme.surface)
            }
            .onChange(of: draft.title) { scheduleDraftSave() }
            .onChange(of: draft.body) { oldValue, _ in
                if applyingHistory { applyingHistory = false }
                else {
                    undoHistory.append(oldValue)
                    if undoHistory.count > 30 { undoHistory.removeFirst() }
                    redoHistory.removeAll()
                }
                scheduleDraftSave()
            }
            .onChange(of: draft.language) { scheduleDraftSave() }
            .onDisappear { saveTask?.cancel(); if !didSave { persistDraftNow() } }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && !didSave && !isSaving { saveTask?.cancel(); persistDraftNow() }
            }
            .alert("清空正文？", isPresented: $confirmingClear) {
                Button("清空正文", role: .destructive) { draft.body = "" }
                Button("取消", role: .cancel) {}
            } message: { Text("可以使用撤销恢复；原资料在保存前不会改变。") }
        }
    }

    private func pasteFromClipboard() {
        guard let value = UIPasteboard.general.string, !value.isEmpty else { saveState = "剪贴板中没有文本"; return }
        draft.body += value
        bodyFocused = true
    }

    private func undoBody() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(draft.body)
        applyingHistory = true
        draft.body = previous
    }

    private func redoBody() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(draft.body)
        applyingHistory = true
        draft.body = next
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleSection
            metadataRow
            bodySection
            SaveStatusView(status: saveState) { scheduleDraftSave(immediate: true) }
            if draft.body.isEmpty { emptyBodyHint }
        }
        .padding(20)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("标题").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            TextField("留空时使用正文首行", text: $draft.title)
                .font(.headline)
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button).stroke(AppTheme.secondarySurface, lineWidth: 1))
                .accessibilityIdentifier("editorTitle")
        }
    }

    private var metadataRow: some View {
        HStack {
            Label("\(AppTheme.languageName(for: draft.language)) · \(draft.language)", systemImage: "character.book.closed")
                .font(.caption.weight(.medium)).foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, AppTheme.Spacing.sm).padding(.vertical, AppTheme.Spacing.xs).background(AppTheme.secondarySurface, in: Capsule())
            Spacer()
            Text("\(draft.body.count) 字").font(.caption).foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("editor.characterCount")
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text("正文").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Button("清空") { confirmingClear = true }.disabled(draft.body.isEmpty).accessibilityIdentifier("editor.clear")
                Button { pasteFromClipboard() } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                    .accessibilityIdentifier("editor.paste")
            }
            TextEditor(text: $draft.body)
                .font(.body).lineSpacing(AppTheme.Spacing.xs).scrollContentBackground(.hidden)
                .padding(AppTheme.Spacing.xs).frame(minHeight: 330)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card).stroke(AppTheme.secondarySurface, lineWidth: 1))
                .focused($bodyFocused).accessibilityIdentifier("editorBody")
        }
    }

    private var emptyBodyHint: some View {
        Label("正文不能为空，添加内容后即可保存。", systemImage: "info.circle")
            .font(.footnote).foregroundStyle(AppTheme.secondaryText)
    }

    private func scheduleDraftSave(immediate: Bool = false) {
        saveTask?.cancel()
        draft.updatedAt = Date()
        saveState = "保存中…"
        let current = draft
        saveTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            do {
                try await store.repository.saveDraft(current)
                await store.refresh()
                if !Task.isCancelled { saveState = "已保存到本机" }
            } catch {
                if !Task.isCancelled { saveState = "保存失败，内容仍保留在编辑器中：\(error.localizedDescription)" }
            }
        }
    }

    private func persistDraftNow() {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft.updatedAt = Date()
        let current = draft
        Task {
            do { try await store.repository.saveDraft(current); await store.refresh() }
            catch { await MainActor.run { saveState = "保存失败，内容仍保留在编辑器中：\(error.localizedDescription)" } }
        }
    }

    private func saveDocument() {
        guard canSave else { return }
        bodyFocused = false
        isSaving = true
        saveTask?.cancel()
        let value = draft
        Task {
            let title = value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String((value.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "新建文本").prefix(40))
                : value.title.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if let id = value.documentID {
                    _ = try await store.repository.updateText(id: id, title: title, body: value.body)
                } else {
                    let saved = try await store.repository.createText(title: title, body: value.body, folderID: value.folderID, language: value.language)
                    draft.documentID = saved.id
                    store.editorDraft = draft
                }
                try await store.repository.removeDraft(id: value.id)
                await store.refresh()
                didSave = true
                store.editorDraft = nil
                dismiss()
            } catch {
                await store.refresh()
                store.errorMessage = error.localizedDescription
                saveState = "保存失败，内容仍保留在编辑器中：\(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func finishAndDismiss() {
        bodyFocused = false
        saveTask?.cancel()
        dismiss()
    }
}

private struct SaveStatusView: View {
    let status: String
    let retry: () -> Void

    private var failed: Bool { status.hasPrefix("保存失败") }
    private var icon: String {
        if failed { return "exclamationmark.circle" }
        if status == "已保存到本机" { return "checkmark.circle.fill" }
        return "info.circle"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(status).lineLimit(2)
            Spacer(minLength: 4)
            if failed { Button("重试", action: retry).font(.caption.weight(.semibold)) }
        }
        .font(.caption)
        .foregroundStyle(failed ? AppTheme.destructive : AppTheme.secondaryText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
