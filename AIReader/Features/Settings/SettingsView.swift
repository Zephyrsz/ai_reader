import SwiftUI
import ReaderCore

public struct SettingsView: View {
    @Environment(AppStore.self) private var store

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.successSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("内容留在你的设备").font(.headline)
                        Text("本地资料库 · 无需登录").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    LocalBadge()
                }
                .readerCard()

                SettingsSection(title: "阅读与语音") {
                    SettingsLink(icon: "waveform", title: "语音与语言", detail: "日本語 · 4 个音色") {
                        VoiceSettingsView().toolbar(.visible, for: .navigationBar)
                    }.accessibilityIdentifier("settings.voice")
                    SettingsLink(icon: "slider.horizontal.3", title: "默认语速", detail: String(format: "%.2f×", store.preferences.defaultRate)) {
                        SpeedSheet().toolbar(.visible, for: .navigationBar)
                    }.accessibilityIdentifier("settings.speedLink")
                    SettingsLink(icon: "textformat.size", title: "阅读显示", detail: "字号 · 行距") {
                        ReadingAppearanceSheet().toolbar(.visible, for: .navigationBar)
                    }.accessibilityIdentifier("settings.readingAppearance")
                    SettingsLink(icon: "circle.lefthalf.filled", title: "外观", detail: store.preferences.appearance.label) {
                        ReadingAppearanceSheet().toolbar(.visible, for: .navigationBar)
                    }.accessibilityIdentifier("settings.appearance")
                }

                SettingsSection(title: "本地数据") {
                    SettingsLink(icon: "externaldrive", title: "存储与缓存", detail: "查看实际占用") {
                        StorageSettingsView().toolbar(.visible, for: .navigationBar)
                    }.accessibilityIdentifier("settings.storage")
                    NavigationLink {
                        TrashView()
                    } label: {
                        SettingsRow(icon: "trash", title: "最近删除", detail: "30 天内可恢复")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
                    .accessibilityIdentifier("settings.trash")
                }

                SettingsSection(title: "关于") {
                    SettingsLink(icon: "info.circle", title: "关于 AI Reader", detail: "版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")") {
                        AboutView()
                    }.accessibilityIdentifier("settings.about")
                }

                Text("资料保存在本机，本 App 不向服务器发送内容。日语朗读在本机离线完成。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var body: some View {
        List {
            Section("AI Reader") {
                LabeledContent("版本", value: version)
                Text("日语优先的本地文本与 PDF 阅读工具。资料管理和阅读不需要账户或服务器。")
            }
            Section("当前能力") {
                Text("支持四个日语音色、试听、逐句朗读、后台音频和锁屏控制。其他语言暂不支持朗读。")
                Text("语音由 VOICEVOX Core 与专用 ONNX Runtime 在本机生成。")
            }
            Section("语音许可") {
                NavigationLink("音色署名与开源许可") { SpeechNoticesView() }
            }
            Section("问题反馈") {
                Text("反馈时请记录 App 版本、iOS 版本、操作步骤和文件格式；无需提供私人原文。当前版本没有在线反馈或自动日志上传。")
            }
        }
        .navigationTitle("关于 AI Reader").navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(AppTheme.background)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.text)
            VStack(spacing: 0) { content }
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.secondarySurface, lineWidth: 0.7))
        }
    }
}

private struct SettingsLink<Destination: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            SettingsRow(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 64) }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 44)
            Text(title).font(.body.weight(.medium)).foregroundStyle(AppTheme.text)
            Spacer(minLength: 8)
            Text(detail).font(.footnote).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

