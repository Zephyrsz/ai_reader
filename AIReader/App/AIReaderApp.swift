import SwiftUI
import UniformTypeIdentifiers
import ReaderCore
import UIKit

@main
struct AIReaderApp: App {
    @State private var store = AppStore.makeDefault()

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    RootView().environment(store)
                } else {
                    StorageRecoveryView()
                }
            }
        }
    }
}

struct StorageRecoveryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地资料库", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("资料库读取失败。为保护现有文件，应用没有覆盖或重建资料。请保留本机数据并重新启动；如果问题持续，请先备份设备数据再联系支持。")
        }
        .padding()
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    private let importTypes: [UTType] = [.pdf, .plainText, .utf8PlainText, UTType(filenameExtension: "md") ?? .plainText]

    private var readerIsVisible: Bool {
        switch store.selectedTab {
        case .home: return !store.homePath.isEmpty
        case .library: return !store.libraryPath.isEmpty
        case .settings: return !store.settingsPath.isEmpty
        }
    }

    var body: some View {
        TabView(selection: Bindable(store).selectedTab) {
            NavigationStack(path: Bindable(store).homePath) {
                HomeView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: UUID.self) { ReaderView(documentID: $0) }
            }
            .tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
            NavigationStack(path: Bindable(store).libraryPath) {
                LibraryView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: UUID.self) { ReaderView(documentID: $0) }
            }
            .tabItem { Label("文件库", systemImage: "folder") }.tag(AppTab.library)
            NavigationStack(path: Bindable(store).settingsPath) {
                SettingsView()
                    .navigationDestination(for: UUID.self) { ReaderView(documentID: $0) }
            }
            .tabItem { Label("设置", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.playback.hasSession && !readerIsVisible {
                HStack(spacing: 8) {
                    Button {
                        if let id = store.playback.documentID { store.openDocument(id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.playback.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(store.playback.status).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button { store.playback.isActive ? store.playback.pause() : store.playback.resume() } label: {
                        Image(systemName: store.playback.isActive ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(store.playback.isActive ? "暂停朗读" : "继续朗读").accessibilityIdentifier("miniplayer.toggle")
                    Button { store.playback.stop() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("停止朗读").accessibilityIdentifier("miniplayer.stop")
                }.padding(.horizontal, 16).padding(.vertical, 6).background(AppTheme.surface)
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(store.preferences.appearance == .system ? nil : store.preferences.appearance == .dark ? .dark : .light)
        .fileImporter(isPresented: Bindable(store).showFileImporter, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): if !urls.isEmpty { store.importRequest = ImportRequest(urls: urls) }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: Bindable(store).importRequest) { request in ImportFlowView(urls: request.urls) }
        .sheet(isPresented: Binding(get: { store.editorDraft != nil }, set: { if !$0 { store.editorDraft = nil } })) {
            if let draft = store.editorDraft { EditorView(draft: draft) }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            store.importRequest = ImportRequest(urls: [url])
        }
    }
}
