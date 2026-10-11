"""Committed editor interchange: derived/editor_chunks <-> editor_export/editor_chunks.tar.xz.

Standard library only, so CI and fresh clones can rebuild the generated chunk scenes
without the raw lidar cache or the GIS stack:

  python3 tools/world/reality/export_pack.py pack      # after export-editor
  python3 tools/world/reality/export_pack.py unpack    # before the Godot generator
  python3 tools/world/reality/export_pack.py verify    # unpacked files match the manifest

The archive is byte-reproducible for identical input (sorted members, zeroed metadata).
"""
from __future__ import annotations

import hashlib
import io
import json
import lzma
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reality import paths  # noqa: E402

SRC = paths.REALITY / "derived" / "editor_chunks"
PACK_DIR = paths.REALITY / "editor_export"
ARCHIVE = PACK_DIR / "editor_chunks.tar.xz"
MANIFEST = PACK_DIR / "manifest.json"
SCHEMA = "kw_reality.editor_export_pack.v1"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _members() -> list[Path]:
    return sorted(p for p in SRC.iterdir() if p.suffix in (".json", ".f32"))


def pack() -> dict:
    files = _members()
    if not files:
        raise SystemExit(f"nothing to pack in {paths.rel(SRC)}; run export-editor first")
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for p in files:
            data = p.read_bytes()
            info = tarfile.TarInfo(p.name)
            info.size, info.mtime, info.mode, info.uid, info.gid, info.uname, info.gname = len(data), 0, 0o644, 0, 0, "", ""
            tar.addfile(info, io.BytesIO(data))
    raw = buf.getvalue()
    packed = lzma.compress(raw, preset=6)
    PACK_DIR.mkdir(parents=True, exist_ok=True)
    ARCHIVE.write_bytes(packed)
    export_manifest = json.loads((SRC / "manifest.json").read_text(encoding="utf-8"))
    doc = {
        "schema": SCHEMA,
        "export_version": export_manifest.get("export_version"),
        "exported_at": export_manifest.get("exported_at"),
        "archive": {"path": paths.rel(ARCHIVE), "bytes": len(packed), "sha256": _sha(packed), "tar_sha256": _sha(raw)},
        "files": {p.name: {"bytes": p.stat().st_size, "sha256": _sha(p.read_bytes())} for p in files},
        "rebuild": "python3 tools/world/reality/export_pack.py unpack && xvfb-run godot --path . --rendering-driver vulkan "
                   "--script tools/world/reality_gen/generate_key_west_chunks_cli.gd -- --verify-digest",
        "digest": paths.rel(PACK_DIR / "generated_digest.json"),
    }
    MANIFEST.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "archive_bytes": len(packed), "tar_bytes": len(raw)}))
    return doc


def unpack() -> int:
    doc = json.loads(MANIFEST.read_text(encoding="utf-8"))
    packed = ARCHIVE.read_bytes()
    if _sha(packed) != doc["archive"]["sha256"]:
        raise SystemExit(f"{paths.rel(ARCHIVE)} does not match its manifest (sha256)")
    SRC.mkdir(parents=True, exist_ok=True)
    for stale in [*SRC.glob("*.json"), *SRC.glob("*.f32")]:
        if stale.name not in doc["files"]:
            stale.unlink()
    with tarfile.open(fileobj=io.BytesIO(lzma.decompress(packed)), mode="r") as tar:
        for member in tar.getmembers():
            if not member.isfile() or "/" in member.name or member.name not in doc["files"]:
                raise SystemExit(f"unexpected archive member {member.name!r}")
            (SRC / member.name).write_bytes(tar.extractfile(member).read())
    return verify()


def verify() -> int:
    doc = json.loads(MANIFEST.read_text(encoding="utf-8"))
    bad = [name for name, rec in doc["files"].items()
           if not (SRC / name).exists() or _sha((SRC / name).read_bytes()) != rec["sha256"]]
    if bad:
        raise SystemExit(f"{len(bad)} interchange files differ from the manifest, e.g. {bad[:3]}")
    print(json.dumps({"verified_files": len(doc["files"])}))
    return len(doc["files"])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd not in ("pack", "unpack", "verify"):
        raise SystemExit(__doc__)
    {"pack": pack, "unpack": unpack, "verify": verify}[cmd]()
