# CPU 与 Core ML／ANE 分支

更新：2026-10-25（Asia/Shanghai）。两个项目采用同名本地分支，未推送远程。

| 分支 | 用途 | AI Reader 起点 | VV 服务起点 |
|---|---|---|---|
| `main` | 已保存的原始基线 | `3edcff1` | `d704b51` |
| `feature/cpu-baseline` | 四音色原生 CPU 版本，可独立继续维护 | `3edcff1` | `d704b51` |
| `feature/coreml-ane` | Core ML／ANE 独立开发，继承 CPU 回退能力 | `3edcff1` 后的开发提交 | `d704b51` 后的开发说明 |

CPU 分支包含已集成的 VOICEVOX Core C ABI／专用 ORT CPU、四个原有音色、词典、播放与后台音频、缓存及其验证材料。它不包含本轮新增的帧契约、回退包装器、缓存后端切换逻辑或 ANE 开发测试。基线中保留的 ANE 可行性分析只是历史文档，不是已启用的功能。这里的 CPU 版本指当前 iOS 原生实现；不能理解为已提供 Windows、Android 等平台运行库。

## ANE 分支当前交付

- `TalkDecoderContract.swift`：有界帧特征、38 帧边缘静音、固定桶尾部静音、严格波形长度校验、裁剪及 PCM WAV 编码。
- `FallbackSpeechRuntime.swift`：可选首选后端的准备／预测失败后释放资源，锁定 CPU 回退，保留失败原因；取消不触发后端切换。
- `LocalSpeechService.swift`：prepare 后选择缓存身份，预测中回退后使用最终后端身份保存音频。
- 3 项帧处理测试、7 项回退／缓存测试及设计、实施计划。

这批内容是可测试的基础组件。App 当前仍直接使用 `VoicevoxNativeRuntime` 的 CPU 路径，尚未使用回退包装器；没有 Core ML 模型加载、预测执行器、帧特征 ABI 提供方或候选模型包校验工具。没有将现有 `vv_bin` 转为 Core ML，也没有 ANE 加速结果。

后续按 [实施计划](superpowers/plans/2026-10-24-coreml-talk.md) 推进。实际接入需要兼容的 Core ML 模型与原生特征接口；模拟器数学测试不能替代真实模型听感和真机 ANE 验证。

## 切换

先保存当前修改；两个项目分别执行相同命令：

```sh
git switch feature/cpu-baseline
# 或继续 ANE 开发：
git switch feature/coreml-ane
```

共同修复先在 CPU 分支验证，再择需合入 ANE；ANE 实验、模型接口和专属测试只提交至 ANE 分支。`main` 本次不合并、不改写。

## 本次分离验证

- 在 `feature/cpu-baseline` 实际检出并运行 ReaderCore：30 项通过；与 `main` 内容完全相同。
- 在 `feature/coreml-ane` 运行 ReaderCore：40 项通过；其中新增 3 项帧契约、7 项回退与缓存测试。
- ANE 分支的 App 原生测试：9 项通过，包含四个真实音色合成；iPhone 17e／iOS 27 模拟器，0 跳过、0 运行时警告。
- ANE 分支 arm64 iPhone Release 未签名构建通过；本次没有真机部署或 ANE 性能测试，也没有重新运行完整 UI 套件。
- VV 服务 CPU 分支 Python 7 项、浏览器播放 6 项通过；ANE 分支服务端代码相同，仅新增分支说明与验证记录。

记录见 [本地验证证据](verification/branch-split-2026-10-25/)。原生测试的 Xcode 日志有系统 build-number 解析诊断，但测试摘要的 `runtimeWarnings` 为空；不能将此描述为整份构建日志没有任何诊断。
