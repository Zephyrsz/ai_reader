# 本地架构与 TTS 扩展边界

2026-10-24 · 原生 TTS 集成后架构。当前工程为 SwiftUI / iOS 17+，日语语音由 C ABI / Rust Core 在本机 CPU 合成。详见 [集成记录](native-tts-integration.md)。

## 1. 已采用的技术

- SwiftUI + Observation：页面和 `@MainActor AppStore` 状态。
- Foundation / CryptoKit Swift Package `ReaderCore`：资料库、草稿、编码、查询、SHA256 去重；不依赖界面或服务器。
- PDFKit：逐页提取文字、显示 PDF 原文、页码跳转、目录与缩略图。
- 系统 `fileImporter` 与 `onOpenURL`：本地文件选择和从其他 App 打开文件。
- 当前未采用 SwiftData、SQLite、账户、网络 SDK 或远程 TTS。

## 2. 模块和调用关系

```text
AIReaderApp → RootView / NavigationStack / TabView
  ├─ Home / Library / Editor / Settings
  ├─ ImportFlowView → 本地 staging → TextDecoder / PDFKit
  └─ ReaderView → SwiftUI 文本 / PDFView
       ↓
  AppStore（主线程快照、导航、错误反馈）
       ↓ await
  LibraryRepository actor（校验、串行访问、磁盘提交）
       ├─ library.json：文件夹与默认偏好
       ├─ Documents/<UUID>/document.json：正文、元数据、书签、位置
       ├─ Documents/<UUID>/original.<ext>：导入原件
       ├─ Drafts/<UUID>.json：未提交编辑
       └─ Caches/Exports/<UUID>/<title>.txt：可重建导出副本

  Reader / Preview / Remote controls → SpeechPlaybackCoordinator
    → 当前句 + 下一句 → LocalSpeechService（串行队列 / WAV 缓存）
    → VoicevoxNativeRuntime → C ABI / Rust Core → 专用 ORT CPU
    → 24 kHz WAV → AVFoundation / 后台音频
```

## 3. 数据与保存规则

`ReaderDocument` 包含 ID、标题、正文、来源格式、BCP-47 语言标签、创建/修改/打开时间、内容 revision、收藏、文件夹、原件路径、源内容 hash、PDF 页文本、阅读位置、书签、删除日期和可选语速覆盖值。

- 新文本默认 `ja-JP`。导入的中文/英文标签只描述内容，未表示相应 TTS 已可用。
- 每份文档单独写 JSON；`Data.write(options: .atomic)` 成功后才替换内存记录。
- 用户编辑导入 TXT/MD 的阅读正文不会覆盖原件；导出 TXT 反映当前正文，“分享原文件”保留原件。
- 正文变化增加 revision 并重置位置；书签按摘录尝试重定位，无法定位时保留摘录并标记失效。只改标题不增加正文 revision。
- 阅读位置为段落/页索引及文本进度；滚动时延迟保存，离场及进入后台触发立即提交。朗读保存当前段落；不提供词级时间轴。
- 草稿约 500ms 延迟保存，退出编辑或进入后台提交当前内容；显式保存正文后移除对应草稿。
- 全局偏好保存在 catalog；单文档语速保存在对应文档；0.5–2.0× 映射到原生 AudioQuery 的 speedScale；偏好新增 voice 并兼容旧记录。

## 4. 错误和恢复

- 损坏的文档/草稿记录被跳过并提示，原文件保留；catalog 损坏或版本不兼容时停止打开，避免重建覆盖。
- 导入记录在原件和元数据写入成功后才出现；提交失败清理该次未完成文档目录。内容 SHA256 用于去重，支持显式导入副本。
- 最近删除保留 30 天，启动/刷新时清理过期项；活跃文档不能直接永久删除。
- 重置先准备空库和恢复标记，再切换目录；中断时下次启动恢复原库或继续清理已确认重置的备份。
- **多文档管理按记录逐项提交，并非跨文档事务。** 磁盘失败时可能部分完成；UI 会刷新真实快照并显示错误，应按剩余资料重试。永久删除支持已删除 ID 的安全重试。
- 当前 JSON schemaVersion 为 1；新增持久字段时需要提供兼容解码或迁移，不能直接丢弃旧目录。

## 5. 导入与解析

文件访问安全作用域只覆盖复制阶段；原文件复制进沙盒后不再依赖外部 URL 长期权限。每项任务具有等待、复制、解析、保存、完成、失败、重复和取消状态。保存阶段阻止关闭；其他阶段取消后忽略迟到结果并清理 staging。

TXT / MD 自动处理 UTF-8 与 BOM 标记的 UTF-16/UTF-32，支持手动 UTF-8、UTF-16、Shift-JIS、GB18030 预览；拒绝不可解码数据和 NUL，不使用有损替换。统一换行，MD 作为纯文本阅读。

PDF 后台逐页提取，保存原页文本和含页标记的阅读正文。密码仅用于当前解锁，不存储；再次打开加密 PDF 可能需要再输入密码。无文字或部分空页明确提示；扫描版仍可查看原文。缩略图按进入目录页面的需要生成，未建立独立缩略图缓存。

限制：50 MB / 20 万字符 / 1000 页。解析取消目前通过忽略结果实现；正在进行的 PDFKit 提取可能继续到任务结束，临时文件随后清理。复杂阅读顺序、竖排精排和 OCR 不在 M0 内。

## 6. 当前原生 TTS

`LocalSpeechService` 实现 `TTSEngine`，并提供带 `SpeechVoice` 的合成重载。Swift 调用官方 C API，底层保留 Rust Core。资源校验、推理、WAV 校验及磁盘缓存均在串行队列；同一时刻只加载一个 VVM，0/8 共用 0.vvm，14 使用 1.vvm，24 使用 8.vvm。

`SpeechPlaybackCoordinator` 由 AppStore 持有，负责播放状态、句预取、系统音频、后台、锁屏和取消。资料 revision、删除、音色和语速变化会失效旧结果。C 调用不能硬中断，完成后检查取消再丢弃输出。语音缓存位于系统 Caches/Speech-v1，独立于资料库，最多约 96 MiB，可在设置清理。

## 7. 能力边界

当前为 CPU 2 线程，不包含 Core ML / ANE。支持句导航及段落高亮，不提供词时间戳、任意音频拖动或定时停止；按句 WAV 播放可能存在句间间隙。iOS 后台音频不是独立系统守护进程。其他语言仍需独立资源与读音适配，完整的资源/许可/验证和真机待验项见 [native-tts-integration.md](native-tts-integration.md)。

## 8. 隐私与验证范围

应用没有上传接口、分析 SDK 或登录。用户主动使用系统分享时，由用户选择目标；文件提供者和系统备份行为受 iOS/用户设置管理。真实朗读使用 UIBackgroundModes/audio；没有麦克风权限或内容上传接口。

构建、测试和具体未验证项见 [implementation-status.md](implementation-status.md)。API 的实际编译兼容性由 Xcode 构建确认；iOS 17 最低版本设备尚需真机验证。
