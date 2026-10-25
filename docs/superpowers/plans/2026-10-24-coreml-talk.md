# Core ML Talk 开发版 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this approved plan in the current session, task by task. The user explicitly requested development on the existing feature branch.

**Goal:** Deliver a working optional Core ML decoder integration with truthful CPU fallback when upstream artifacts are absent.

**Architecture:** Keep the existing serial speech service. Feed bounded features from a versioned optional native frontend into a hash-verified fixed-shape Core ML decoder; release the preferred runtime before CPU fallback. Cache by the runtime that actually generated each WAV.

**Tech Stack:** Swift, C ABI, Core ML, XCTest, Python development tooling.

**Spec:** [Core ML Talk design](../specs/2026-10-24-coreml-talk-design.md)

**2026-10-25 分支整理：** `feature/cpu-baseline` 保留 CPU 基线；本计划与新增实现仅在 `feature/coreml-ane`。当前已完成帧处理和回退／缓存基础组件，尚未接通 Core ML 模型或 App 运行时工厂。详见 [分支说明](../../branches.md)。

## Global Constraints

- 最低 iOS 17；24 kHz mono PCM；style 0/8/14/24。
- 一条串行推理队列；只驻留当前模型/桶；不引入 Python/WSS 到 App。
- 不转换 vv_bin；无兼容模型或前端时明确使用 CPU。
- Core ML 的计算单元请求不等于 ANE 实际执行证据。

## Task 1: Frame and manifest contracts

Files: `Sources/ReaderCore/TalkDecoderContract.swift`, `Tests/ReaderCoreTests/TalkDecoderTests.swift`.

- [x] Write tests for 38-frame silence padding, right bucket padding, exact cropping and frame/NaN/range rejection.
- [x] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter TalkDecoderTests`; confirm missing implementation fails.
- [x] Implement `TalkFrameFeatures` and `TalkFramePlan` with checked limits; 3 tests passed before adding fallback tests, and pass in the full suite.
- [ ] Implement and test `CoreMLTalkManifest` with strict schema and content-bound identity. No manifest implementation is included yet.

## Task 2: Runtime fallback and effective cache identity

Files: `Sources/ReaderCore/FallbackSpeechRuntime.swift`, `Sources/ReaderCore/LocalSpeechService.swift`, `Tests/ReaderCoreTests/FallbackSpeechTests.swift`.

- [x] Test prepare failure, prediction failure, release-before-fallback, sticky fallback, cancellation and output cache ownership with real service/cache I/O.
- [x] Observe red tests before implementing `FallbackSpeechRuntime` and moving cache-key selection after prepare/rechecking after inference.
- [x] Run `swift test --filter FallbackSpeechTests` and the existing speech tests. Also verify retry after failed CPU preparation and release after preferred-runtime recreation.

## Task 3: Optional native frontend and actual Core ML execution

Files: `Sources/VoicevoxFeatureABI/include/voicevox_feature_abi.h`, `Sources/VoicevoxFeatureABI/lookup.c`, `Sources/ReaderCore/TalkFeatureFrontend.swift`, `Sources/ReaderCore/CoreMLTalkRuntime.swift`, `AIReader/Speech/SpeechRuntimeFactory.swift`, `AIReader/Speech/VoicevoxNativeRuntime.swift`, `AIReader/Speech/SpeechPlaybackCoordinator.swift`, `Package.swift`.

- [ ] Test absent ABI, rejected versions/mapping, valid/invalid compiled model metadata and prediction/cropping using a clearly labeled mathematical test graph.
- [ ] Implement an optional ABI lookup, bounded copy/free ownership, Core ML model loading, one-bucket residency and float32 WAV output.
- [ ] Integrate the factory in the existing app coordinator. Reuse native asset verification before calling the frontend; leave CPU runtime output unchanged.
- [ ] Run native tests against all four actual voices through the new app factory.

## Task 4: Upstream package tooling and integration documentation

Files in `vv_tts_server`: `tools/coreml/validate_candidate.py`, `tests/test_coreml_candidate.py`, `docs/coreml/README.md`, ABI header copy. Files in `ai_reader`: `Scripts/install_coreml_candidate.py`, `docs/coreml-talk-development.md`.

- [ ] Test malformed manifests, incompatible source models, missing/extra files, symlinks/traversal and per-bucket checksums; observe red before implementing the validator.
- [ ] Provide validation/install commands for authorized precompiled model packages. No model conversion or runtime downloads.
- [ ] Document the C ABI provider obligations and exact candidate schema, plus the remaining upstream dependencies.

## Task 5: Verification and evidence

- [ ] Run all ReaderCore tests, native regression tests, candidate-validator/server tests and arm64 iPhone Release build.
- [ ] Record actual outcomes, runtime selection and simulator/device limits under `docs/verification/coreml-talk/`.
- [ ] Review changes against the design, update integration status/README, and preserve work on `feature/coreml-ane` without merging or pushing.
