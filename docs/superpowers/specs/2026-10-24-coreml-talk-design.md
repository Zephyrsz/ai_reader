# Core ML Talk decoder 开发版

依据用户已授权的 [ANE 方案](../../../../vv_tts_server/docs/analysis/2026-10-24-ane-adaptation-optimization.md)，在 `feature/coreml-ane` 开发，不改变 `main` 的 CPU 基线。

## 本版边界

实现可执行的 Core ML decoder、版本化前端 C ABI 消费端、资源交付校验、固定长度桶、静音 padding/裁剪、CPU 回退与缓存隔离。保持最低 iOS 17、24 kHz mono PCM、四个已有 style 0/8/14/24、单串行推理和单模型驻留。

当前没有获准的 Core ML 音色模型，也没有原 Core Talk 帧特征 ABI 提供方。这两个输入缺失时 App 自动使用现有 CPU 引擎。本版不转换或解包保护格式，不复制 Rust 的特征生成算法，不把 Core ML 配置等同于实际 ANE 执行。

## 接口与数据

新增 `VoicevoxFeatureABI` C 模块，以 `dlsym` 查询可选的 `voicevox_talk_frontend_get_api_v1`，校验 ABI 版本、结构大小、函数指针及实现身份。提供方须复用原 Core 的查询、时长/音高、语速和帧展开；只加载前端所需 Session，不能同时常驻原 CPU decoder。生成的帧不含 decoder padding，携带内部 speaker ID 和来源 VVM SHA256，不能将 style ID 直接当 speaker ID。

`TalkFrameFeatures` 验证 F、两个输入的同步长度、45 音素通道、有限浮点数和非负内部 speaker。现有 Talk 两端各加 38 帧 silence，额外长度桶 padding 置于右端，f0=0、phoneme 第 0 通道=1。输出长度必须为 B×256，截取 `[38×256, (38+F)×256)`。单段有效音频不超过 30 秒。原生 Core ML 边界将内部 int64 speaker 检查后转换为 int32；外部 f0/phoneme/wave 均为 float32。

候选包为 `Voicevox/CoreMLTalk/manifest.json` 加预编译 `.mlmodelc` 文件。清单绑定原始 VVM 内容、style→内部 speaker 映射、前端实现身份、导出器/精度、计算单元策略和每个编译文件的 SHA256。只接受全部四音色、严格文件清单和已记录桶 padding 对齐验证的包。固定桶避免 iOS 17 多动态输入枚举限制；只驻留当前模型/桶。模型元数据必须与清单声明的固定 shape/dtype/name 一致。开发工具验证和原生验证执行相同约束；开发工具不负责证明音质。

## 运行时与回退

App 工厂默认尝试自动选择；无模型、无前端、校验失败或预测失败时记录明确原因，并释放首选后端再准备 CPU。本次进程内锁定回退，防止逐句重试失败路径；取消不触发回退。诊断只描述所请求的计算单元及实际使用的运行库，不声称已在 ANE 执行。

`LocalSpeechService` 在 prepare 后读取缓存身份，并在合成后再次读取身份，确保一次预测中切换后端的结果落入真实后端的缓存。Core ML 身份包含清单内容 hash、策略和 OS；CPU 保持原有身份。模型、权重、桶、精度、导出器变化均导致候选身份改变。

## 验收

先写行为测试，再实现。覆盖帧边界、silence/crop、溢出/NaN、模型/音色映射、ABI 缺失、清单与文件校验、模型元数据、Core ML 实际 CPU 预测、回退释放顺序、取消及缓存归属。Core ML 数学测试图只用于测试；不作为 TTS 模型或四音色替身。四音色继续运行真实 CPU 合成回归。执行 ReaderCore、原生测试和 arm64 iPhone Release 构建，保存证据。

真机签名、原模型的 Core ML 数值/听感对齐、ANE 分配与持续功耗均为后续硬件/上游验收，不能以模拟器或数学测试图替代。
