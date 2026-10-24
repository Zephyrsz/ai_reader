# Native Japanese TTS Implementation Plan

> Execute inline with the executing-plans skill; the user already requested implementation of the reviewed architecture.

**Goal:** Integrate the four existing voices into offline reading and preview using native runtime calls.

**Architecture:** ReaderCore owns speech requests, Japanese segments, WAV validation and a serial service with bounded hash-addressed audio cache. The iOS adapter owns Core C pointers; a single main-actor coordinator owns playback and one-sentence prefetch.

**Tech Stack:** Swift 5.9+, iOS 17+, SwiftUI, CryptoKit, AVFoundation, MediaPlayer, VOICEVOX Core 0.17.0, dedicated ORT 1.23.2.

**Spec:** `docs/superpowers/specs/2026-10-24-native-tts-design.md`.

## Global constraints

- Keep iOS 17 minimum. Use styles 0/8/14/24 and existing VVM contents.
- No WSS/HTTP/Python dependency in the app; CPU backend until a compatible Core ML runtime/model exists.
- One native queue, one active model, current sentence plus one prefetch; no false hard-cancellation claim.
- Preserve existing library data. Keep changes in this workspace (AI Reader is not a Git checkout); retain a pre-change source snapshot in `/tmp/ai-reader-before-native-tts-20261024`.

## Tasks

- [x] 1. Add failing ReaderCore speech tests and run `swift test --filter Speech` to prove missing behavior. Implement typed voice requests, bounded Japanese segmentation, WAV validation, serial service, cancellation, bounded disk cache and backward-compatible preferences. Run the full package tests.
- [x] 2. Prepare pinned upstream XCFrameworks and copy existing three VVM files/dictionary/policies with a hash manifest using `python3 Scripts/prepare_voicevox.py`. Add native integration tests first; implement the C ABI adapter and Xcode link/embed/resource/test configuration. Build and run the four actual voices on simulator.
- [x] 3. Implement the single AVFoundation playback coordinator, current+next pipeline, pause/skip/stop, interruption/route handling and background audio. Wire AppStore, reader, settings previews, rate changes, following and mini player. Update UI tests before enabling the controls and run playback scenarios.
- [x] 4. Verify missing/corrupt resources, cancellation after text/rate/voice changes and native model switching. Build Release for arm64 device, inspect signing availability, run all relevant tests, and save measured evidence plus setup/license/ANE limitations in documentation.

The source files and script interfaces are described in the spec. Each task is reviewed inline against the spec before continuing; no commits or new Git repository are created.

## Verification outcome

Core: 30 tests passed. Native: 9 tests passed with all four real styles and no runtime warnings. Full UI: 12 tests passed with no runtime warnings; final reading and storage smoke tests passed after the progress-write and reset-cache changes. Release arm64 iPhone architecture builds successfully unsigned. Physical-device installation is unavailable because the host has zero valid signing identities. Core ML/ANE remains blocked on upstream runtime/model delivery, as documented in the approved design. Evidence: `docs/verification/native-tts/` and `docs/native-tts-integration.md`.
