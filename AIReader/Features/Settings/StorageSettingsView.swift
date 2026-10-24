import SwiftUI
import ReaderCore

public struct StorageSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var usage = StorageUsage()
    @State private var speechBytes = 0
    @State private var isLoading = true
    @State private var showResetConfirmation = false

    public init() {}

    public var body: some View {
        List {
            Section("占用空间") {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    storageRow("原文件", bytes: usage.documents, icon: "doc")
                    storageRow("草稿", bytes: usage.drafts, icon: "square.and.pencil")
                    storageRow("缓存", bytes: usage.caches, icon: "archivebox")
                    HStack {
                        Text("总计").font(.headline)
                        Spacer()
                        Text(Self.byteString(usage.total)).font(.headline.monospacedDigit())
                    }
                }
            }
            Section {
                Button {
                    Task { await clearCaches() }
                } label: {
                    Label("清理导出缓存", systemImage: "trash.slash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isLoading || usage.caches == 0)
                .accessibilityIdentifier("storage.clearExportCache")
                Text("只清理可重新生成的 TXT 导出缓存，不会删除原文件、正文或书签。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
            Section("语音缓存") {
                storageRow("已生成的语音", bytes: Int64(speechBytes), icon: "waveform")
                Button("清理语音缓存并停止朗读") {
                    Task {
                        do { try await store.playback.clearAudioCache(); await loadUsage() }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                }.frame(minHeight: 44).disabled(isLoading).accessibilityIdentifier("storage.clearSpeechCache")
                Text("缓存最多保留约 96 MB，可随时重新生成。随附模型和日语词典约 270 MB，不属于可清理缓存。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
            Section("危险操作") {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("清空资料库", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("storage.resetLibrary")
                Text("会删除本地资料、草稿、书签和文件夹，无法恢复。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("存储与缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadUsage() }
        .sheet(isPresented: $showResetConfirmation) { ResetLibrarySheet { await resetLibrary() } }
    }

    private func storageRow(_ title: String, bytes: Int64, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.secondaryText).frame(width: 30, height: 44)
            Text(title).foregroundStyle(AppTheme.text)
            Spacer()
            Text(Self.byteString(bytes)).foregroundStyle(AppTheme.secondaryText).monospacedDigit()
        }
    }

    private func loadUsage() async {
        isLoading = true
        do {
            usage = try await store.repository.storageUsage()
            speechBytes = try await store.playback.service.cacheSize()
        } catch {
            store.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func clearCaches() async {
        guard await store.perform({ try await $0.clearCaches() }) else { return }
        await loadUsage()
    }

    private func resetLibrary() async -> Bool {
        do { try await store.playback.clearAudioCache() }
        catch { store.errorMessage = error.localizedDescription; return false }
        guard await store.perform({ try await $0.resetLibrary() }) else { return false }
        await loadUsage()
        return true
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

private struct ResetLibrarySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let confirm: () async -> Bool
    @State private var step = 1
    @State private var isResetting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("第 \(step) / 2 次确认", systemImage: "exclamationmark.triangle")
                        .font(.title3.weight(.semibold)).foregroundStyle(AppTheme.destructive)
                    Text(step == 1
                         ? "清空会删除本地正文、导入原文件、草稿、书签和文件夹。请先导出需要保留的内容。"
                         : "所有本地资料都会永久删除，阅读设置也会恢复默认。此操作无法撤销。")
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(AppTheme.destructive) }
                    Button(role: .destructive) {
                        if step == 1 { step = 2 }
                        else {
                            isResetting = true
                            Task { @MainActor in
                                if await confirm() { dismiss() }
                                else { errorMessage = store.errorMessage ?? "清空未完成，请重试。"; store.errorMessage = nil }
                                isResetting = false
                            }
                        }
                    } label: {
                        Text(isResetting ? "正在清空…" : step == 1 ? "继续" : "删除所有本地资料")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.destructive)
                    .disabled(isResetting).accessibilityIdentifier(step == 1 ? "storage.continueReset" : "storage.confirmReset")
                }.padding(24)
            }
            .background(AppTheme.background)
            .navigationTitle(step == 1 ? "清空资料库？" : "永久清空资料库？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isResetting) } }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isResetting)
    }
}
