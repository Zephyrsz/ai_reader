# iOS M0 Implementation Plan

**Goal:** 实现已确认的 SwiftUI 本地文本、文件阅读与资料管理版本；不合成或模拟语音。

**Architecture:** Foundation/CryptoKit 核心 Swift Package 管本地持久化与规则；SwiftUI iOS App 管页面与状态；PDFKit 负责 PDF。每份资料单独原子落盘，App 不依赖服务器。

**Tech Stack:** Swift 5.9+、iOS 17+、SwiftUI、Observation、PDFKit、UniformTypeIdentifiers。

**Spec:** `docs/product-spec.md` 和 `design-system/ai-reader/MASTER.md`。用户于 2026-10-23 明确批准按既有路线实现。

## Global Constraints

- 先完成 M0.1–M0.3；TTS、后台音频、音色下载与 OCR 保留明确未就绪状态。
- 文本和文件只存本机；不接账户、远程 API 或远程 TTS。
- 支持 PDF/TXT/MD、一层文件夹、最近删除 30 天、日语默认。
- 所有 UI 操作有保存/失败反馈；导入取消和编码错误不产生伪完成记录。
- 已找到 `/Applications/Xcode.app` 的完整 Xcode 27；全局选择器仍指向 CLT，构建命令使用局部 `DEVELOPER_DIR`，不改系统设置。核心测试、iOS 模拟器构建及 XCTest UI 测试均执行，真机另行验收。

## Task 1: 可测试的本地数据闭环

文件：`Package.swift`、`Sources/ReaderCore/{Models,LibraryRepository,TextDecoder,LibraryQuery,TTSEngine}.swift`、`Tests/ReaderCoreTests/`。

主要接口：`LibraryRepository(root:)`；`snapshot()`；`createText(title:body:folderID:language:)`；`updateText(id:title:body:)`；`importDocument(...)`；书签/位置/文件夹/回收站/草稿/偏好。

- [x] 写实际临时目录上的持久化、去重、编码、删除恢复与版本失效测试。
- [x] 用可编译的空实现运行测试，确认行为测试失败。
- [x] 实现逐文档原子落盘、文件复制、SHA256 去重与错误校验，运行 `swift test`。
- [x] 验证损坏记录不被静默覆盖；保存失败时内存状态不提前提交。

## Task 2: SwiftUI 主界面与创作/资料管理

文件：`AIReader/App/`、`AIReader/Design/`、`AIReader/Features/{Home,Library,Editor}/`。

- [x] 建立 AppStore 与核心接口适配；统一错误提示和刷新。
- [x] 首页、文件库、文件夹、搜索筛选/排序、批量移动/删除/收藏、最近删除。
- [x] 编辑器标题/正文/主动粘贴/字数、500ms 草稿保存、失败保留与恢复。
- [x] 使用原生分享导出；所有危险操作有确认。

## Task 3: 文件导入与阅读器

文件：`AIReader/Features/Import/`、`AIReader/Features/Reader/`。

- [x] fileImporter 取得权限后复制到 staging，确认编码/语言/文件夹再导入。
- [x] TXT/MD UTF-8/BOM 解码，手动 Shift-JIS/GB18030 等预览；重复文件可打开已有或导入副本。
- [x] PDF 密码解锁、原文/文本模式、页码/缩略图/目录、无文字页提示。
- [x] 文本查找/书签/进度恢复、PDF 文本副本编辑、字号行距和主题。
- [x] 语速仅保存偏好；播放按钮禁用且无假时间轴。

## Task 4: 设置、工程和交付验证

文件：`AIReader/Features/Settings/`、`AIReader.xcodeproj/`、`README.md`、`docs/implementation-status.md`。

- [x] 设置与实际存储容量、缓存清理、重置确认、日语引擎未接入页。
- [x] 创建共享 Xcode scheme、资源、隐私声明；不添加无用途权限或后台模式。
- [x] `swift test` 全绿；解析所有 Swift；实际 iOS SDK 完整构建与原生 UI 测试；结果见 implementation-status。
- [x] 检查工程引用和资源路径、所有主要入口与错误恢复；记录真机和无障碍验证边界。

当前目录不是 Git 仓库；直接在用户指定目录执行，不初始化 Git、不虚构提交记录。

## 执行记录

2026-10-24：四项实现任务已落地；集成测试发现并修复 PDF 首次导入入口和编辑器工具栏导航问题。最终测试数量、结果、截图与剩余设备验收项以 `docs/implementation-status.md` 为准。本计划保留为实施过程记录，不表示真实 TTS 已接入。
