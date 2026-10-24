#!/usr/bin/env python3
"""Prepare pinned iOS runtimes and existing four-voice resources; development only."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ARCHIVES = [
    ("core_xcframework.zip", "https://github.com/VOICEVOX/voicevox_core/releases/download/0.17.0/voicevox_core-xcframework-0.17.0.zip", "e634b0fd7e09924a4c9c4f6e8b5c0da0790a7649d89f289cbcad1b97976212be", "voicevox_core.xcframework"),
    ("voicevox_onnxruntime-ios-xcframework-1.23.2.zip", "https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-1.23.2/voicevox_onnxruntime-ios-xcframework-1.23.2.zip", "c9c33b2653125441d6a2475194ed7971a908687c0d99d8944337b0ca85ea646d", "voicevox_onnxruntime.xcframework"),
]
NOTICES = {
    "VOICEVOX-Core-LICENSE.txt": "https://raw.githubusercontent.com/VOICEVOX/voicevox_core/0.17.0/LICENSE",
    "ONNX-Runtime-LICENSE.txt": "https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.2/LICENSE",
    "ONNX-Runtime-ThirdPartyNotices.txt": "https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.2/ThirdPartyNotices.txt",
    "VOICEVOX-model-terms.md": "https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/0.16.0/README.md",
}

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def download(url, path):
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    path.write_bytes(data)

def prepare(source, cache):
    info = json.loads((source / "assets/models/BUILD_INFO.json").read_text())
    expected = {0, 8, 14, 24}
    assert {v["style_id"] for m in info["models"] for v in m["voices"]} == expected
    for model in info["models"]:
        path = source / "assets/models" / model["file"]
        if sha(path) != model["output_sha256"]:
            raise ValueError(f"Model checksum mismatch: {path}")
    cache.mkdir(parents=True, exist_ok=True)
    vendor = ROOT / "Vendor"
    vendor.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ai-reader-voicevox-") as temp:
        staging = Path(temp)
        for name, url, expected_hash, framework in ARCHIVES:
            archive = cache / name
            if not archive.exists():
                download(url, archive)
            if sha(archive) != expected_hash:
                raise ValueError(f"Archive checksum mismatch: {archive}")
            unpack = staging / framework
            unpack.mkdir()
            subprocess.run(["ditto", "-x", "-k", str(archive), str(unpack)], check=True)
            extracted = next(unpack.rglob(framework))
            target = vendor / framework
            if target.exists(): shutil.rmtree(target)
            shutil.copytree(extracted, target, symlinks=True)
            # Upstream ORT 1.23.2 uses an underscore in CFBundleIdentifier.
            # Normalize metadata only; Xcode signs the embedded frameworks for the app.
            for plist in target.rglob("Info.plist"):
                if plist.is_symlink(): continue
                metadata = plistlib.loads(plist.read_bytes())
                identifier = metadata.get("CFBundleIdentifier", "")
                if "_" in identifier:
                    metadata["CFBundleIdentifier"] = identifier.replace("_", "-")
                    plist.write_bytes(plistlib.dumps(metadata))
            # XCTest loads processed frameworks from Build/Products via DYLD_FRAMEWORK_PATH.
            # The upstream fat simulator ORT signature is invalid; prepare valid local
            # ad-hoc signatures as well as Xcode's normal CodeSignOnCopy in the app.
            for bundle in target.glob("*simulator/*.framework"):
                subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(bundle)], check=True)
        assets = staging / "Voicevox"
        (assets / "models").mkdir(parents=True)
        for model in info["models"]:
            shutil.copy2(source / "assets/models" / model["file"], assets / "models" / model["file"])
        shutil.copytree(source / "assets/dict/open_jtalk_dic_utf_8-1.11", assets / "dictionary")
        notices = assets / "notices"
        shutil.copytree(source / "character_info", notices / "voices")
        for name, url in NOTICES.items():
            local = cache / name
            if not local.exists(): download(url, local)
            shutil.copy2(local, notices / name)
        shutil.copy2(source / "assets/dict/open_jtalk_dic_utf_8-1.11/COPYING", notices / "Dictionary-COPYING.txt")
        manifest = {"schema": 1, "coreVersion": "0.17.0", "ortVersion": "1.23.2", "backend": "CPU", "files": {}, "voices": []}
        for path in sorted(assets.rglob("*")):
            if path.is_file():
                manifest["files"][str(path.relative_to(assets))] = {"sha256": sha(path), "bytes": path.stat().st_size}
        for model in info["models"]:
            manifest["voices"].extend({**voice, "model": model["file"]} for voice in model["voices"])
        identity = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        manifest["identity"] = hashlib.sha256(identity).hexdigest()
        (assets / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        target = ROOT / "NativeAssets/Voicevox"
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(assets, target)
    print(f"Prepared Core 0.17.0 / dedicated ORT 1.23.2; styles {sorted(expected)}")
    print(f"Resource identity: {manifest['identity']}; {len(manifest['files'])} verified files")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT.parent / "vv_tts_server")
    parser.add_argument("--download-cache", type=Path, default=ROOT / ".build/voicevox-downloads")
    args = parser.parse_args()
    prepare(args.source.resolve(), args.download_cache.resolve())
