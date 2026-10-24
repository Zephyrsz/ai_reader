import SwiftUI
import ReaderCore

public struct VoiceSettingsView: View {
    @Environment(AppStore.self) private var store
    public init() {}

    public var body: some View {
        List {
            Section {
                Label("日本語 · 离线朗读", systemImage: "waveform")
                Text("四个音色已随 App 安装，无需下载。首次准备或切换音色可能稍需等待。试听会替换当前朗读。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
            Section("音色") {
                ForEach(SpeechVoice.allCases) { voice in
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                var preferences = store.preferences
                                preferences.voice = voice
                                await store.savePreferences(preferences)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(voice.name).font(.body.weight(.medium))
                                    Text(voice.style).font(.caption).foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                if store.preferences.voice == voice { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent) }
                            }.frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("voice.select.\(voice.rawValue)")
                        .accessibilityLabel("选择 \(voice.name)，\(voice.style)")
                        .accessibilityValue(store.preferences.voice == voice ? "已选择" : "未选择")
                        Button {
                            store.playback.preview(voice, rate: store.preferences.defaultRate)
                        } label: { Image(systemName: "play.circle").font(.title2).frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("试听 \(voice.name)")
                            .accessibilityIdentifier("voice.preview.\(voice.rawValue)")
                    }
                }
            }
            if store.playback.hasSession {
                Section {
                    Text(store.playback.status).accessibilityIdentifier("voice.status")
                    Button("停止朗读 / 试听") { store.playback.stop() }
                        .frame(minHeight: 44).accessibilityIdentifier("voice.stop")
                }
            }
            Section {
                NavigationLink("音色署名与使用许可") { SpeechNoticesView() }
                Text("生成语音的使用需要遵守各音色的使用条款；导出或公开使用语音时，请保留对应署名。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background)
        .navigationTitle("语音与语言").navigationBarTitleDisplayMode(.inline)
    }
}

struct SpeechNoticesView: View {
    private var notices: [URL] {
        let root = Bundle.main.bundleURL.appendingPathComponent("Voicevox/notices")
        return (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension != "json" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    var body: some View {
        List {
            Section("音色署名") {
                ForEach(SpeechVoice.allCases) { voice in Text("\(voice.credit) · \(voice.style)") }
            }
            Section("随附许可原文") {
                ForEach(notices, id: \.path) { url in
                    NavigationLink(url.lastPathComponent == "policy.md" ? String(url.deletingLastPathComponent().lastPathComponent.prefix { $0 != "_" }) + " 使用条款" : url.lastPathComponent) {
                        ScrollView {
                            Text((try? String(contentsOf: url, encoding: .utf8)) ?? "无法读取许可文件")
                                .font(.footnote).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                        }.navigationTitle(url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }.navigationTitle("署名与许可").navigationBarTitleDisplayMode(.inline)
    }
}
