import Foundation
import CryptoKit
import ReaderCore
import voicevox_core

/// Owned by the speech service's serial queue, including every C pointer below.
final class VoicevoxNativeRuntime: SpeechRuntime, @unchecked Sendable {
    private struct Manifest: Decodable {
        struct File: Decodable { let sha256: String; let bytes: Int }
        let identity: String
        let coreVersion: String
        let ortVersion: String
        let backend: String
        let files: [String: File]
    }

    let cacheIdentity: String
    private let resourceDirectory: URL
    private let manifest: Manifest?
    private var verified = false
    private var synthesizer: OpaquePointer?
    private var loadedModel: String?
    private var loadedID: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)?

    init(resourceDirectory: URL) {
        self.resourceDirectory = resourceDirectory
        let data = try? Data(contentsOf: resourceDirectory.appendingPathComponent("manifest.json"))
        manifest = data.flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        cacheIdentity = "voicevox-c-api-v1-threads2-" + (manifest?.identity ?? "missing")
    }

    deinit { releaseResources() }

    func prepare() throws {
        if synthesizer != nil { return }
        guard let manifest, manifest.backend == "CPU", manifest.coreVersion == "0.17.0", manifest.ortVersion == "1.23.2" else {
            throw SpeechError.resource("缺少兼容的资源清单，请重新构建并安装 App。")
        }
        if !verified {
            // Verify once off the main thread, before any native pointer is created.
            for (relative, expected) in manifest.files {
                guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw SpeechError.resource("资源路径无效") }
                let url = resourceDirectory.appendingPathComponent(relative)
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count == expected.bytes,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected.sha256 else {
                    throw SpeechError.resource("\(relative) 缺失或校验失败，请重新安装。")
                }
            }
            for file in ["models/0.vvm", "models/1.vvm", "models/8.vvm", "dictionary/sys.dic", "dictionary/char.bin", "dictionary/matrix.bin", "dictionary/unk.dic"] {
                guard manifest.files[file] != nil else { throw SpeechError.resource("资源清单缺少 \(file)") }
            }
            verified = true
        }
        var ort: OpaquePointer?
        try check(voicevox_onnxruntime_init_once(&ort))
        guard let ort else { throw SpeechError.native("无法初始化推理库") }
        var jtalk: OpaquePointer?
        try check(voicevox_open_jtalk_rc_new(resourceDirectory.appendingPathComponent("dictionary").path, &jtalk))
        guard let jtalk else { throw SpeechError.native("无法初始化日语词典") }
        defer { voicevox_open_jtalk_rc_delete(jtalk) }
        var options = voicevox_make_default_initialize_options()
        options.acceleration_mode = Int32(VOICEVOX_ACCELERATION_MODE_CPU.rawValue)
        // Reader background work leaves CPU capacity for rendering/audio. Tune on devices separately.
        options.cpu_num_threads = 2
        try check(voicevox_synthesizer_new(ort, jtalk, options, &synthesizer))
    }

    func synthesize(_ request: SpeechRequest) throws -> Data {
        try prepare()
        guard let synthesizer else { throw SpeechError.native("引擎未就绪") }
        try load(request.voice, into: synthesizer)
        var queryPointer: UnsafeMutablePointer<CChar>?
        try check(voicevox_synthesizer_create_audio_query(synthesizer, request.text, request.voice.rawValue, &queryPointer))
        guard let queryPointer else { throw SpeechError.native("查询为空") }
        defer { voicevox_json_free(queryPointer) }
        let raw = Data(String(cString: queryPointer).utf8)
        guard var query = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { throw SpeechError.native("查询格式错误") }
        query["speedScale"] = request.rate
        query["outputSamplingRate"] = 24_000
        query["outputStereo"] = false
        // Bound the work using actual predicted durations, including punctuation and speed.
        let phrases = query["accent_phrases"] as? [[String: Any]] ?? []
        let moras = phrases.flatMap { ($0["moras"] as? [[String: Any]] ?? []) + (($0["pause_mora"] as? [String: Any]).map { [$0] } ?? []) }
        let seconds = moras.reduce(0.0) { $0 + ($1["consonant_length"] as? Double ?? 0) + ($1["vowel_length"] as? Double ?? 0) }
        let edges = (query["prePhonemeLength"] as? Double ?? 0) + (query["postPhonemeLength"] as? Double ?? 0)
        guard (seconds + edges) / request.rate <= 30 else { throw SpeechError.segmentTooLong }
        let modified = try JSONSerialization.data(withJSONObject: query)
        guard let json = String(data: modified, encoding: .utf8) else { throw SpeechError.native("无法编码查询") }
        var count = 0
        var wav: UnsafeMutablePointer<UInt8>?
        try check(voicevox_synthesizer_synthesis(synthesizer, json, request.voice.rawValue, voicevox_make_default_synthesis_options(), &count, &wav))
        guard let wav else { throw SpeechError.invalidAudio }
        defer { voicevox_wav_free(wav) }
        return Data(bytes: wav, count: count)
    }

    func releaseResources() {
        if let synthesizer { voicevox_synthesizer_delete(synthesizer) }
        synthesizer = nil; loadedModel = nil; loadedID = nil
    }

    private func load(_ voice: SpeechVoice, into synthesizer: OpaquePointer) throws {
        if loadedModel == voice.modelFile { return }
        if var id = loadedID {
            try withUnsafePointer(to: &id) { try check(voicevox_synthesizer_unload_voice_model(synthesizer, $0)) }
            loadedModel = nil; loadedID = nil
        }
        var file: OpaquePointer?
        try check(voicevox_voice_model_file_open(resourceDirectory.appendingPathComponent("models/\(voice.modelFile)").path, &file))
        guard let file else { throw SpeechError.resource(voice.modelFile) }
        defer { voicevox_voice_model_file_delete(file) }
        var id = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
        voicevox_voice_model_file_id(file, &id)
        try check(voicevox_synthesizer_load_voice_model(synthesizer, file, voicevox_make_default_load_voice_model_options()))
        loadedID = id; loadedModel = voice.modelFile
    }

    private func check(_ code: Int32) throws {
        guard code == VOICEVOX_RESULT_OK.rawValue else { throw SpeechError.native(String(cString: voicevox_error_result_to_message(code))) }
    }
}
