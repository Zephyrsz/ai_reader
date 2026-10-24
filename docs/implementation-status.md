# 实现与验证记录

更新：2026-10-24（Asia/Shanghai） · 版本 0.1.0（1） · 最低 iOS 17

## 当前：原生日语 TTS 集成

已实现四个现有音色的原生 CPU 推理、试听、逐句播放、暂停/跳句、段落跟随、后台音频/锁屏控制和有界语音缓存。App 不依赖 Python、WSS 或服务器。Core ML / ANE 尚未实现。旧资料库和偏好兼容。

验证：核心 30 项、原生 9 项、完整 UI 12 项通过；原生和 UI 均无运行时警告。最终阅读/存储专项各 1 项通过，arm64 iPhone Release 未签名构建通过。本机无有效签名身份，未部署真机。

当前代码、固定资源、真实音频、测量数据、测试及构建以 [原生 TTS 集成记录](native-tts-integration.md) 和 [对应证据](verification/native-tts/) 为准。下面保留首次 M0 交付的历史记录；其中“未接入语音”描述不再代表当前代码。

---

# M0 历史实现与验证记录

## 交付范围

本次交付是可构建的 SwiftUI 原生项目和真实本地数据功能，沿用四张参考图的阅读工具设计。实施顺序为：文本编辑与保存 → 导入/PDF/资料管理。日语 TTS 和其他语言朗读保留到后续；没有音频合成、伪播放、模型下载或远程服务。

| 模块 | 当前实现 |
|---|---|
| 首页 | 新建、主动粘贴、导入、最近添加、继续阅读、草稿恢复提示 |
| 文本编辑 | 标题/正文、字数、确认清空、30 步正文撤销/重做、500ms 草稿保存、后台/离场保存、空白校验、失败保留与重试 |
| 导入 | 系统多文件选择、外部 file URL 打开、本地原件、PDF/TXT/MD、编码预览、内容去重、打开已有/导入副本、取消/重试和单项结果 |
| 文本阅读 | 文本选择、查找与计数、书签、段落位置与阅读进度、字号/行距、Dynamic Type、原件/TXT 分享 |
| PDF | 原文/文本模式、PDFKit 缩放/滚动、页码输入、缩略图、大纲、查找、密码解锁、空页/扫描提示、提取文字副本编辑 |
| 文件库 | 搜索标题/正文、排序、格式/收藏筛选、一层文件夹、新建/改名/移动/删除文件夹、单项/批量收藏/移动/回收 |
| 最近删除 | 30 天保留、恢复、确认永久删除、启动/刷新时过期清理 |
| 设置 | 深浅/系统主题、字号/行距、默认/单文档语速偏好、恢复默认、待接入语音说明、实际容量、清理导出缓存、两次确认清空、版本与隐私说明 |
| 语音扩展入口 | TTSEngine 协议与 UnavailableTTSEngine；播放/跳句/试听禁用，语速和跟随只保存用户偏好 |

“导入/上传”在本项目中指复制到 App 本机沙盒，不是上传服务器。读取系统文件提供者上的云盘文件可能触发系统下载。中文/英文内容标签不表示已经提供这些语言的语音引擎。

## 构建与运行

使用完整 Xcode 打开 [AIReader.xcodeproj](../AIReader.xcodeproj)，选择 **AIReader** scheme 和模拟器。真机需要在 Signing & Capabilities 配置自己的开发团队。当前项目无第三方包依赖，ReaderCore 是项目内本地 Swift Package。

本机全局选择器指向 CLT，因此所有验证使用命令级 `DEVELOPER_DIR`；没有修改全局 Xcode 配置。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AIReader.xcodeproj -scheme AIReader \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO test
```

UI 测试通过 DEBUG 环境变量选择独立的 `UITests-<UUID>` 根目录，不读写正常的 `AIReader` 资料库。Release 不提供测试资料库选择入口。

## 验证结果

- 核心套件：**21 项通过，0 失败**。覆盖日语保存/重开、空文校验、原件复制/内容去重、正文 revision 与失效书签、草稿/偏好、文件夹删除、回收/过期清理、损坏文件保留、失败写入、编码、查询、重置中断恢复和 unavailable TTS。
- 原生 UI：**10 项通过，0 失败、0 跳过、0 运行时警告**，iPhone 17e / iOS 27 模拟器（390pt 宽）。覆盖日语创建/编辑/重启、查找/书签、草稿恢复、清空/撤销/重做、收藏回收/恢复、TXT 去重、文件夹移动/正文搜索、横屏、PDF 双模式、语速保存、缓存清理与两步重置。
- 构建：Debug 原生编译与测试通过；Release / arm64 模拟器构建通过。Xcode 27.0（27A266a）。AppIntents 的未依赖提示为工具元数据跳过警告，没有 Swift 编译错误。
- 全量 UI 测试结束：2026-10-24 00:40:10（Asia/Shanghai）。结果文件 `.build/results/AIReaderUITests-15.xcresult`；可携带摘要见 [UI 结果 JSON](verification/2026-10-24-ui-summary.json)、[核心测试记录](verification/2026-10-24-core-tests.txt)、[UI 测试记录](verification/2026-10-24-ui-tests.txt)、[Release 构建记录](verification/2026-10-24-release-build.txt)。
- 实现截图：**13 张实际原生截图**，见 [截图索引](../design/implemented/index.html) 和 [四个主要界面总览](../design/implemented/native-overview.png)；来源对应测试名称保存在 manifest.json。
- 截图复核：横屏增加窗口与控件布局检查，改为等待布局后获取完整屏幕，并将 EXIF 方向转换为实际像素方向；[横屏专项复测](verification/2026-10-24-landscape-test.txt) 1 项通过，2026-10-24 00:44:25 结束。最终截图与文档的本地链接、PNG 完整性均已核对。

集成测试曾发现并修复：PDF 首次导入按钮漏显、普通文本查找计数、正文导出在编辑后刷新、阅读位置离场提交，以及编辑器键盘工具栏布局问题。导航采用每个 Tab 独立 NavigationStack。回收站行内的恢复/永久删除按钮使用独立按钮样式，避免整行同时触发多个操作；返回与其他功能使用真实控件点击测试。正文清空使用标准确认弹窗；资料库重置使用同一面板中的两步确认，避免连续系统弹窗丢失第二次确认。

## 持久化与保护

```text
Application Support/AIReader/
  library.json
  Documents/<UUID>/document.json
  Documents/<UUID>/original.<ext>
  Drafts/<UUID>.json
  Caches/Exports/<UUID>/<title>.txt
```

逐记录原子写入成功后才提交内存状态；损坏记录保留并提示。catalog 无法读取时停止打开，不静默重建。资料库重置有恢复标记与目录切换保护。

多文档操作逐项提交，磁盘错误时可能部分完成，**不是跨文档事务**。UI 刷新真实结果并显示失败；用户可按剩余项目重试。文档原件和编辑正文独立，修改文本不覆盖导入原文件。

## 边界与后续

- 单文件 ≤50 MB，正文 ≤20 万字符，PDF ≤300 页。这些是保护阈值，不是所有设备上的性能承诺。
- PDF 阅读顺序依赖原文字层；扫描件只展示原文，没有 OCR。PDF 密码不持久保存；重新打开时可能要求再次解锁。
- 导入解析取消后忽略结果；正在执行的 PDFKit 解析可能继续到结束，随后清理临时文件。
- 真机、iOS 17 设备、iPad、完整 VoiceOver、系统减少动态效果和长文压力/耗电还需专项验收；模拟器验证不等同于 App Store 发布验收。
- 后续接入真实日语端侧 TTS，再开放音频会话、真实播放/暂停/跳句、高亮、锁屏/后台、定时停止与音色资源。其他语言在 ja-JP 验收后逐个扩展。
- Share Extension、OCR、EPUB/DOCX、资料备份迁移和复杂竖排尚未实现。

完整阶段安排见 [roadmap.md](roadmap.md)，实际模块和接口边界见 [architecture.md](architecture.md)。
