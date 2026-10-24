# Native Japanese speech integration

The user's instruction authorizes implementation of the reviewed ANE adaptation report in AI Reader. This delivery implements the available native CPU path and app integration. Core ML/ANE cannot be enabled by a flag in the supplied vv_bin runtime; no acceleration claim or remote fallback will be added.

## Architecture

SwiftUI → one application playback coordinator → bounded sentence synthesis/prefetch → serial native speech service → VOICEVOX Core 0.17.0 C ABI / existing Rust implementation → dedicated ORT 1.23.2 CPU → 24 kHz WAV → AVFoundation.

The service runs within the app on a background queue, not as an iOS daemon or localhost network server. Audio playback uses the supported background audio mode; a finite background task bridges short synthesis gaps. The system may still suspend or terminate the app.

Use the existing four styles: 0 四国めたん/あまあま and 8 春日部つむぎ/ノーマル share 0.vvm; 14 冥鳴ひまり/ノーマル uses 1.vvm; 24 WhiteCUL/たのしい uses 8.vvm. Load one VVM at a time and unload on model change. Do not create four permanently resident runtimes.

## Behavior

- Preserve the existing ReaderCore protocol with a voice-aware service overload. Validate language, style, speed, blank/NUL input and synthesis limits.
- Segment Japanese by punctuation and paragraph; preserve closers and paragraph mapping; bound long sentences. Do not claim word timings or neural streaming.
- Cache actual WAV files under a bounded disk budget. Content identity includes model/dictionary/runtime hashes, voice, text and speed. Validate WAV before use and regenerate corrupt entries.
- Serialize all C calls off the main thread. Cancellation invalidates queued and late results immediately; it does not promise interruption of an active C inference.
- Play/pause/stop, previous/next sentence, selected voice preview, persistent voice choice, document/global rate, reading follow, background audio and remote controls all use the same coordinator.
- Editing, deleting, changing voice/rate or starting another document invalidates obsolete output. Returning from the reader retains the session and exposes a mini player.
- Existing preference JSON must decode with the default voice when the new field is absent. Unsupported languages stay readable and report speech unavailability.
- Preserve model metadata and actual weights, include existing voice policies and upstream license notices. Resources are bundled for offline operation.

## Validation

ReaderCore tests exercise segmentation, old preferences, file cache identity/corruption/eviction and queued/in-flight cancellation. Native integration tests use all four actual VVM styles on iOS simulator and inspect non-silent 24 kHz WAV output, model switching and speed changes. UI tests exercise voice selection/preview and actual reading playback, pause and skip. Build Debug simulator and Release device architectures. A paired device may be used only if normal signing is available; lack of signing is reported, not bypassed. Record actual backend, measured scope, and remaining ANE and physical-device work.
