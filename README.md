# AI Reader · iOS 本地阅读

SwiftUI 原生 iOS 项目，最低 **iOS 17**。支持本机文本/PDF 阅读和四个日语音色的离线朗读。语音直接调用 **VOICEVOX Core（C ABI / Rust）+ 专用 ONNX Runtime CPU**，无需 Python、HTTP、WSS 或服务器。

四个现有音色：四国めたん（0）、春日部つむぎ（8）、冥鳴ひまり（14）、WhiteCUL（24）。模型和词典随 App 安装。**当前尚未接入 Core ML / ANE**。

[原生 TTS 实现、测量及验证说明](docs/native-tts-integration.md)

## 运行

资源已准备在 `Vendor/` 与 `NativeAssets/`；需重新生成时先运行 `python3 Scripts/prepare_voicevox.py --source ../vv_tts_server`（仅开发准备使用 Python）。

1. 用完整 Xcode 打开 `AIReader.xcodeproj`，选择共享 scheme **AIReader**。
2. 选择 iPhone 模拟器并运行；目标最低版本 **iOS 17**。
3. 安装到自己的 iPhone 时，在 Signing & Capabilities 中选择自己的开发团队。

若全局 `xcode-select` 指向 Command Line Tools，可仅为本次命令指定 Xcode：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AIReader.xcodeproj -scheme AIReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
```

模拟器名称按本机已安装设备替换。UI 测试将最后的 `build` 改为 `test`；测试数据使用独立资料库，不会混入正常运行的资料。

## 当前功能

- **首页**：新建、主动粘贴、文件导入、继续阅读和最近添加。
- **编辑器**：标题/正文、字数、撤销/重做、草稿自动保存与重启恢复；空白正文不可提交。
- **文件导入**：系统文件选择和“用 AI Reader 打开”，支持多文件 PDF / TXT / MD；复制到私有目录、编码预览、文件内容去重和单项重试。
- **阅读器**：文本查找、书签、位置记录、字号/行距/主题、原文件和 TXT 副本分享；PDF 原文/文本切换、页码、缩略图、大纲和密码解锁。
- **日语朗读**：播放/暂停/停止、跳句、段落跟随、最多一句预取、后台音频和锁屏控制；原生串行推理、单个活跃模型、96 MiB 语音缓存。
- **资料管理**：本地搜索、排序、格式与收藏筛选、一层文件夹、重命名、移动、批量管理；最近删除保留 30 天，可恢复或确认永久删除。
- **设置**：实际存储统计、清理导出缓存、两次确认重置、默认/单文档语速、四音色选择和试听、语音缓存清理、离线署名和许可。

单文件上限 50 MB、正文上限 20 万字符、PDF 上限 1000 页。扫描 PDF 可保留原文查看；当前不做 OCR。PDF 文字顺序取决于文件文字层，复杂版式可能需要人工校正。

## 工程结构

```text
AIReader/                   SwiftUI 页面、状态、PDFKit 桥接与资源
Sources/ReaderCore/         本地数据、编码、查询、分句与原生服务队列
Tests/ReaderCoreTests/      文件系统级核心测试
AIReaderUITests/            原生端到端界面测试
AIReaderNativeTests/        四个真实音色与播放会话测试
NativeAssets/Voicevox/      固定模型、词典、清单和许可
Vendor/                    官方固定版本 XCFrameworks
docs/                       功能规格、实现现状、架构与后续分期
design/                     原始设计评审稿与实现截图
```

持久数据位于应用沙盒的 `Application Support/AIReader/`。JSON 逐记录原子保存，导入原件独立保留。本 App 不发送资料到服务器；通过系统文件提供者选择云盘文件时，系统可能需要先下载文件，系统备份也属于设备设置范围。

## 交付入口

- [原生 TTS 集成与验证](docs/native-tts-integration.md)：真实四音色输出、测试、构建、资源复现与限制。
- [实现现状与历史验证记录](docs/implementation-status.md)
- [13 张实际原生截图](design/implemented/index.html) · [四个主要界面总览](design/implemented/native-overview.png)
- [架构与 TTS 接口边界](docs/architecture.md)
- [开发分期](docs/roadmap.md)
- [产品规格](docs/product-spec.md)
- [设计系统](design-system/ai-reader/MASTER.md)
- [原始静态设计](design/index.html)

更新日期：2026-10-24。arm64 真机架构构建已通过；本机无可用签名身份，尚未安装真机。iPhone 实际性能、长时间锁屏、热状态和耗电需要真机验收。
