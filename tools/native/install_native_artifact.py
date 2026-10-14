#!/usr/bin/env python3
"""Download, verify, and install the CI-built Hoarbound GDExtension artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


REPOSITORY = "Nolavel/Hoarbound"
ARTIFACT_NAME = "hoarbound-native"
WORKFLOW = "native-libraries.yml"


def run(command: list[str], cwd: Path | None = None, capture: bool = False) -> str:
	print("+", subprocess.list2cmdline(command), flush=True)
	completed = subprocess.run(
		command,
		cwd=cwd,
		check=True,
		text=True,
		stdout=subprocess.PIPE if capture else None,
	)
	return (completed.stdout or "").strip()


def sha256(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as source:
		for chunk in iter(lambda: source.read(1024 * 1024), b""):
			digest.update(chunk)
	return digest.hexdigest()


def verify_artifact(artifact: Path) -> dict[str, object]:
	manifest_path = artifact / "manifest.json"
	checksums_path = artifact / "SHA256SUMS.txt"
	if not manifest_path.is_file() or not checksums_path.is_file():
		raise SystemExit("Artifact is missing manifest.json or SHA256SUMS.txt")

	manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
	if manifest.get("schema") != 2:
		raise SystemExit(f"Unsupported native artifact schema: {manifest.get('schema')}")

	for raw_line in checksums_path.read_text(encoding="utf-8").splitlines():
		expected, relative = raw_line.split("  ", 1)
		path = artifact / relative
		if not path.is_file():
			raise SystemExit(f"Artifact file is missing: {relative}")
		actual = sha256(path)
		if actual != expected:
			raise SystemExit(f"Checksum mismatch for {relative}: {actual}")
	return manifest


def install(artifact: Path, repository: Path) -> dict[str, object]:
	manifest = verify_artifact(artifact)
	for relative in (Path("bin"), Path("addons/hoarbound_native")):
		source = artifact / relative
		if not source.is_dir():
			raise SystemExit(f"Artifact directory is missing: {relative.as_posix()}")
		shutil.copytree(source, repository / relative, dirs_exist_ok=True)
	return manifest


def latest_run_id(branch: str) -> str:
	if not shutil.which("gh"):
		raise SystemExit("GitHub CLI is required. Install it and run: gh auth login")
	result = run(
		[
			"gh", "run", "list",
			"--repo", REPOSITORY,
			"--workflow", WORKFLOW,
			"--branch", branch,
			"--status", "success",
			"--limit", "1",
			"--json", "databaseId",
			"--jq", ".[0].databaseId",
		],
		capture=True,
	)
	if not result:
		raise SystemExit(f"No successful {WORKFLOW} run found on branch {branch}")
	return result


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--branch", default="main", help="branch used to select the latest successful workflow run")
	parser.add_argument("--run-id", help="install from an exact successful workflow run")
	parser.add_argument("--artifact-dir", type=Path, help="install an already downloaded artifact directory")
	parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[2])
	args = parser.parse_args()

	repository = args.repository_root.resolve()
	if not (repository / "project.godot").is_file():
		raise SystemExit(f"Not a Hoarbound checkout: {repository}")

	if args.artifact_dir:
		artifact = args.artifact_dir.resolve()
		manifest = install(artifact, repository)
	else:
		if not shutil.which("gh"):
			raise SystemExit("GitHub CLI is required. Install it and run: gh auth login")
		run_id = args.run_id or latest_run_id(args.branch)
		with tempfile.TemporaryDirectory(prefix="hoarbound-native-") as temporary:
			artifact = Path(temporary)
			run(
				[
					"gh", "run", "download", run_id,
					"--repo", REPOSITORY,
					"--name", ARTIFACT_NAME,
					"--dir", str(artifact),
				]
			)
			manifest = install(artifact, repository)

	print(
		"Installed Hoarbound GDExtension from commit "
		f"{manifest['source_commit']} for Godot {manifest['engine']}."
	)
	print("Installed paths: bin/ and addons/hoarbound_native/hoarbound_native.gdextension")
	return 0


if __name__ == "__main__":
	try:
		raise SystemExit(main())
	except subprocess.CalledProcessError as error:
		print(f"Command failed with exit code {error.returncode}", file=sys.stderr)
		raise SystemExit(error.returncode)
