#!/usr/bin/env python3
"""Build and smoke-load Hoarbound's GDExtension on the current CI runner."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


EXPECTED_BINARIES = {
	"windows": "hoarbound_native.dll",
	"linux": "libhoarbound_native.so",
	"macos": "libhoarbound_native.macos.dylib",
}


def run(
	command: list[str],
	cwd: Path,
	capture: bool = False,
	check: bool = True,
) -> subprocess.CompletedProcess[str]:
	print("+", subprocess.list2cmdline(command), flush=True)
	return subprocess.run(
		command,
		cwd=cwd,
		check=check,
		text=True,
		stdout=subprocess.PIPE if capture else None,
		stderr=subprocess.STDOUT if capture else None,
	)


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--platform", choices=sorted(EXPECTED_BINARIES), required=True)
	parser.add_argument("--arch", required=True)
	parser.add_argument("--jobs", type=int, default=2)
	args = parser.parse_args()

	repository = Path(__file__).resolve().parents[2]
	extension_root = repository / "native" / "hoarbound_native"
	test_project = extension_root / "ci_project"
	api_file = test_project / "extension_api.json"
	proof_dir = extension_root / "proof" / args.platform
	dist_dir = extension_root / "dist" / "bin" / args.platform
	build_dir = test_project / "bin" / args.platform
	descriptor_template = extension_root / "hoarbound_native.gdextension.template"
	test_descriptor = test_project / "addons" / "hoarbound_native" / "hoarbound_native.gdextension"

	godot_value = os.environ.get("GODOT_BIN", "")
	if not godot_value:
		raise SystemExit("GODOT_BIN is required")
	godot = Path(godot_value).resolve()
	if not godot.is_file():
		raise SystemExit(f"Godot executable does not exist: {godot}")

	scons = shutil.which("scons")
	if not scons:
		raise SystemExit("scons is not on PATH")
	if not descriptor_template.is_file():
		raise SystemExit(f"Missing descriptor template: {descriptor_template}")

	for directory in (proof_dir, dist_dir):
		if directory.exists():
			shutil.rmtree(directory)
		directory.mkdir(parents=True)
	if build_dir.exists():
		shutil.rmtree(build_dir)
	if test_descriptor.exists():
		test_descriptor.unlink()

	if api_file.exists():
		api_file.unlink()
	run(
		[str(godot), "--headless", "--path", str(test_project), "--dump-extension-api"],
		extension_root,
	)
	if not api_file.is_file() or api_file.stat().st_size == 0:
		raise SystemExit("Godot did not produce extension_api.json")

	run(
		[
			scons,
			f"-j{args.jobs}",
			"target=template_release",
			f"platform={args.platform}",
			f"arch={args.arch}",
			"precision=single",
			f"custom_api_file={api_file}",
		],
		extension_root,
	)

	binary_name = EXPECTED_BINARIES[args.platform]
	binary = build_dir / binary_name
	if not binary.is_file() or binary.stat().st_size == 0:
		raise SystemExit(f"Expected native binary was not produced: {binary}")

	if args.platform == "macos":
		codesign = shutil.which("codesign")
		if not codesign:
			raise SystemExit("codesign is required on the macOS runner")
		run([codesign, "--force", "--sign", "-", str(binary)], extension_root)
		run([codesign, "--verify", "--verbose", str(binary)], extension_root)

	test_descriptor.parent.mkdir(parents=True, exist_ok=True)
	shutil.copy2(descriptor_template, test_descriptor)
	extension_list = test_project / ".godot" / "extension_list.cfg"
	extension_list.parent.mkdir(parents=True, exist_ok=True)
	extension_list.write_text("res://addons/hoarbound_native/hoarbound_native.gdextension\n", encoding="utf-8")
	smoke = run(
		[str(godot), "--headless", "--path", str(test_project), "--script", "res://smoke.gd"],
		repository,
		capture=True,
		check=False,
	)
	output = smoke.stdout or ""
	print(output, end="")
	(proof_dir / "smoke.log").write_text(output, encoding="utf-8")
	if smoke.returncode != 0:
		raise SystemExit(f"Godot native smoke failed with exit code {smoke.returncode}")
	for marker in ("HOARBOUND_FROST_CORE_TRACE=0,250,500,1000,0,500,1000", "HOARBOUND_NATIVE_SMOKE_OK"):
		if marker not in output:
			raise SystemExit(f"Native smoke marker was not emitted: {marker}")

	shutil.copy2(binary, dist_dir / binary_name)
	print(f"Packaged {dist_dir / binary_name}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
