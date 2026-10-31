import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ReaderCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var recoveryCandidate: EditorDraft?
    private var recent: [ReaderDocument] { Array(store.documents.sorted { $0.createdAt > $1.createdAt }.prefix(3)) }
    private var continuing: ReaderDocument? {
        store.documents.filter { ($0.lastOpenedAt != nil) && $0.position.progress < 1 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                if !store.snapshot.loadWarnings.isEmpty {
                    Label("部分资料无法读取，原文件已保留。", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Color(uiColor: .systemOrange)).frame(maxWidth: .infinity, alignment: .leading).readerCard()
                }
                HStack {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(AppTheme.primaryButton, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.input))
                        Text("AI Reader").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.text)
                    }
                    Spacer()
                    LocalBadge()
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("让文字，慢慢说。").font(.largeTitle.bold()).foregroundStyle(AppTheme.text).minimumScaleFactor(0.8)
                    Text("从一段日语，开始今天的阅读。").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("继续阅读").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.text)
                    if let document = continuing {
                        Button { store.openDocument(document.id) } label: {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                HStack { Text(document.kind.label).font(.caption.weight(.medium)).padding(.horizontal, AppTheme.Spacing.xs).padding(.vertical, 6).background(AppTheme.secondarySurface, in: Capsule()); Text("\(AppTheme.languageName(for: document.language)) · \(document.language)").font(.caption).foregroundStyle(AppTheme.secondaryText); Spacer() }
                                Text(document.title).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                ProgressView(value: min(1, max(0, document.position.progress))).tint(AppTheme.accent)
                                HStack { Text("文本进度 \(Int(document.position.progress * 100))%").font(.caption).foregroundStyle(AppTheme.secondaryText); Spacer(); Label("继续阅读", systemImage: "book.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, AppTheme.Spacing.md).padding(.vertical, AppTheme.Spacing.sm).background(AppTheme.primaryButton, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.button)) }
                            }.readerCard()
                        }.buttonStyle(.plain).accessibilityIdentifier("home.continueReading")
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Label("从第一段日语开始", systemImage: "book.closed").font(.headline).foregroundStyle(AppTheme.text)
                            Text("创建一份文本，或导入设备中的 PDF、TXT 和 MD 文件。资料只保存在本机。").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            HStack {
                                Button { store.newText() } label: { Label("新建文本", systemImage: "square.and.pencil") }.buttonStyle(.borderedProminent).tint(AppTheme.primaryButton)
                                Button { store.showFileImporter = true } label: { Label("导入文件", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)
                            }
                        }.readerCard().accessibilityIdentifier("home.emptyState")
                    }
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("开始新阅读").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.text)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppTheme.Spacing.sm) { quickAction("新建文本", subtitle: "自己写一段", icon: "square.and.pencil") { store.newText() }; quickAction("粘贴文本", subtitle: "由你主动粘贴", icon: "doc.on.clipboard") { store.newText(body: UIPasteboard.general.string ?? "") }; quickAction("导入文件", subtitle: "PDF · TXT · MD", icon: "folder") { store.showFileImporter = true } }
                        VStack(spacing: AppTheme.Spacing.xs) { quickAction("新建文本", subtitle: "自己写一段", icon: "square.and.pencil") { store.newText() }; quickAction("粘贴文本", subtitle: "由你主动粘贴", icon: "doc.on.clipboard") { store.newText(body: UIPasteboard.general.string ?? "") }; quickAction("导入文件", subtitle: "PDF · TXT · MD", icon: "folder") { store.showFileImporter = true } }
                    }
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack { Text("最近添加").font(.title3.weight(.semibold)); Spacer(); Button("查看全部") { store.selectedTab = .library }.font(.subheadline.weight(.medium)).accessibilityIdentifier("home.viewAll") }
                        .foregroundStyle(AppTheme.text)
                    if recent.isEmpty {
                        Text("你的本地资料会显示在这里。").font(.subheadline).foregroundStyle(AppTheme.secondaryText).frame(maxWidth: .infinity, alignment: .leading).readerCard()
                    } else {
                        ForEach(recent) { document in
                            Button { store.openDocument(document.id) } label: { DocumentRow(document: document).readerCard() }.buttonStyle(.plain)
                        }
                    }
                }
                Text("内容保存在本机，不会发送到服务器。日语语音在本机离线生成。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, AppTheme.Spacing.xs)
            }.padding(.horizontal, 20).padding(.top, AppTheme.Spacing.md).padding(.bottom, 28)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .task {
            await store.refresh()
            if recoveryCandidate == nil, store.editorDraft == nil {
                recoveryCandidate = store.snapshot.drafts.max { $0.updatedAt < $1.updatedAt }
            }
        }
        .alert("恢复未完成的草稿？", isPresented: Binding(get: { recoveryCandidate != nil }, set: { if !$0 { recoveryCandidate = nil } })) {
            Button("稍后", role: .cancel) { recoveryCandidate = nil }
            Button("恢复") { store.editorDraft = recoveryCandidate; recoveryCandidate = nil }
        } message: { Text("草稿保存在本机，可以继续编辑。") }
    }

    private func quickAction(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.accent).frame(width: 44, height: 44)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.text).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(AppTheme.Spacing.sm).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card))
        }.buttonStyle(.plain).accessibilityIdentifier(title == "新建文本" ? "newText" : "home.action.\(title)")
    }
}
