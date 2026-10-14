#!/usr/bin/env python3
"""Validate and package all three Hoarbound native CI outputs."""

from __future__ import annotations

import argparse

import hashlib
import json
from pathlib import Path
import shutil


EXPECTED = (
	Path("bin/windows/hoarbound_native.dll"),
	Path("bin/linux/libhoarbound_native.so"),
	Path("bin/macos/libhoarbound_native.macos.dylib"),
)
DESCRIPTOR = Path("addons/hoarbound_native/hoarbound_native.gdextension")


def sha256(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as source:
		for chunk in iter(lambda: source.read(1024 * 1024), b""):
			digest.update(chunk)
	return digest.hexdigest()


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--dist", type=Path, required=True)
	parser.add_argument("--descriptor", type=Path, required=True)
	parser.add_argument("--engine-version", required=True)
	parser.add_argument("--godot-cpp-ref", required=True)
	parser.add_argument("--source-commit", required=True)
	args = parser.parse_args()

	dist = args.dist.resolve()
	dist.mkdir(parents=True, exist_ok=True)
	for relative in EXPECTED:
		path = dist / relative
		if not path.is_file() or path.stat().st_size == 0:
			raise SystemExit(f"Missing platform binary: {relative.as_posix()}")

	descriptor = dist / DESCRIPTOR
	descriptor.parent.mkdir(parents=True, exist_ok=True)
	shutil.copy2(args.descriptor.resolve(), descriptor)

	files = []
	for relative in (*EXPECTED, DESCRIPTOR):
		path = dist / relative
		files.append(
			{
				"path": relative.as_posix(),
				"bytes": path.stat().st_size,
				"sha256": sha256(path),
			}
		)

	manifest = {
		"schema": 2,
		"engine": args.engine_version,
		"godot_cpp": args.godot_cpp_ref,
		"source_commit": args.source_commit,
		"files": files,
	}
	manifest_path = dist / "manifest.json"
	manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

	checksum_targets = [dist / relative for relative in (*EXPECTED, DESCRIPTOR)]
	checksum_targets.append(manifest_path)
	checksum_lines = [f"{sha256(path)}  {path.relative_to(dist).as_posix()}" for path in checksum_targets]
	(dist / "SHA256SUMS.txt").write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")

	print(json.dumps(manifest, indent=2))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
