# M0 并行实现接口契约

> 此文保留 M0 规格/接口背景。2026-10-24 已接入原生日语 TTS，当前语音行为与验证以 [native-tts-integration.md](native-tts-integration.md) 为准。

核心真实类型以 `Sources/ReaderCore/Models.swift` 为准。UI 目标 iOS 17 / Swift 5，使用 `@Environment(AppStore.self)`。所有公开数据结构和 Actor 均在 ReaderCore 模块。

## Repository（Actor，所有方法从 UI 使用 await）

```
init(root: URL) throws
snapshot() -> LibrarySnapshot
createText(title: String, body: String, folderID: UUID? = nil, language: String = "ja-JP") throws -> ReaderDocument
updateText(id: UUID, title: String, body: String) throws -> ReaderDocument
rename(id: UUID, title: String) throws
toggleFavorite(id: UUID) throws
move(ids: [UUID], folderID: UUID?) throws
trash(ids: [UUID], now: Date = Date()) throws
restore(ids: [UUID]) throws
deletePermanently(ids: [UUID]) throws
addFolder(name: String) throws -> ReaderFolder
renameFolder(id: UUID, name: String) throws
deleteFolder(id: UUID) throws
recordOpened(id: UUID) throws
setPosition(id: UUID, position: ReadingPosition) throws
addBookmark(id: UUID, paragraphIndex: Int, pageIndex: Int? = nil) throws
removeBookmark(documentID: UUID, bookmarkID: UUID) throws
setPreferences(_ preferences: ReaderPreferences) throws
setDocumentRate(id: UUID, rate: Double?) throws
saveDraft(_ draft: EditorDraft) throws
removeDraft(id: UUID) throws
importDocument(sourceURL: URL, text: String, kind: DocumentKind, pageTexts: [String] = [], allowDuplicate: Bool = false, folderID: UUID? = nil, language: String = "ja-JP") throws -> ReaderDocument
originalURL(for id: UUID) throws -> URL
exportTextURL(for id: UUID) throws -> URL
storageUsage() throws -> StorageUsage
clearCaches() throws
purgeExpiredTrash(now: Date = Date()) throws
resetLibrary() throws
```

核心还有 `TextDecoder.decode(_ data: Data, encoding: TextFileEncoding? = nil) throws -> String`；`TextFileEncoding: String, CaseIterable, Identifiable`（utf8、utf16、shiftJIS、gb18030），含 `label`。

`LibraryQuery.apply(documents: [ReaderDocument], search: String = "", filter: LibraryFilter = .all, sort: LibrarySort = .recentlyOpened, folderID: UUID? = nil, showDeleted: Bool = false) -> [ReaderDocument]`。LibraryFilter = all/text/pdf/favorites；LibrarySort = recentlyOpened/dateAdded/title；均 CaseIterable、Identifiable、有 label。

## 共享 UI（主界面实现者负责）

`@MainActor @Observable final class AppStore`：

```
let repository: LibraryRepository
var snapshot: LibrarySnapshot
var errorMessage: String?
var homePath: [UUID]
var libraryPath: [UUID]
var settingsPath: [UUID]
var editorDraft: EditorDraft?
var importRequest: ImportRequest? // Identifiable，urls: [URL]
var showFileImporter: Bool
var selectedTab: AppTab // home/library/settings
var preferences: ReaderPreferences { get } // snapshot.preferences
var documents: [ReaderDocument] { get } // 非回收站
func document(_ id: UUID) -> ReaderDocument?
func refresh() async
@discardableResult func perform(_ operation: (LibraryRepository) async throws -> Void) async -> Bool
func openDocument(_ id: UUID)
func newText(body: String = "", folderID: UUID? = nil)
func editDocument(_ document: ReaderDocument)
func savePreferences(_ preferences: ReaderPreferences) async
```

`AppTheme.background / surface / secondarySurface / text / secondaryText / accent` 为动态色；`View.readerCard()`；`LocalBadge`；`DocumentRow(document:)`。

UI sheet 约定：`ReaderView(documentID: UUID)`；`ImportFlowView(urls: [URL])`；`SettingsView()`；`VoiceSettingsView()`；`SpeedSheet(documentID: UUID? = nil)`；`ReadingAppearanceSheet()`。

TabView 内每项有独立 NavigationStack；阅读器是 navigationDestination，隐藏 TabBar。各功能可用内部子 View，无需改共享接口。错误用 store.errorMessage，根视图 alert 负责呈现。真正语音全部不实现，相关按钮 disabled 并解释；语速偏好正常保存。

所有实现者不得改其他工作区文件或做 Git 操作；当前目录没有 Git。实现后报告源码解析/构建结果与剩余问题，禁止另开 reviewer。
