#!/usr/bin/env python3
"""Ratchet on node trees built in code (docs/technical/RUNTIME_CONSTRUCTION_AUDIT.md).

Counts `.new()` of visual, physics, light, audio, particle and UI classes, plus primitive meshes and
materials, per tracked .gd under scripts/ and world/, and compares each file with
tools/ci/runtime_construction_baseline.txt. A file may not exceed its baseline, a new file may not start
building content in code, and a file that dropped below its line must lower it (the debt only shrinks).
A line may say `procedural` after '#' when the construction is the procedure (snow clipmap, rigs).
Run: python3 tools/ci/check_runtime_construction.py [--write-baseline]   (exit 1 on a violation)
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "tools/ci/runtime_construction_baseline.txt"
SCANNED = ("scripts/", "world/")
CLASSES = (
    r"MeshInstance3D|MultiMeshInstance3D|Node3D|Marker3D|Label3D|Sprite3D|Decal|CSG\w+"
    r"|StaticBody3D|RigidBody3D|Area3D|CollisionShape3D|\w+Shape3D"
    r"|OmniLight3D|SpotLight3D|DirectionalLight3D|FogVolume|GPUParticles3D|CPUParticles3D"
    r"|AudioStreamPlayer3D|AudioStreamPlayer"
    r"|BoxMesh|CylinderMesh|SphereMesh|CapsuleMesh|PlaneMesh|QuadMesh|PrismMesh|TorusMesh"
    r"|StandardMaterial3D|ShaderMaterial|ParticleProcessMaterial|FogMaterial"
    r"|Label|Button|Panel|PanelContainer|\w+Container|ColorRect|TextureRect|ProgressBar|RichTextLabel"
)
PATTERN = re.compile(r"\b(?:" + CLASSES + r")\.new\(\)")


def count(text: str) -> int:
    return sum(len(PATTERN.findall(line.split("#", 1)[0])) for line in text.splitlines())


def scan(root: Path) -> dict:
    files = subprocess.run(["git", "ls-files", "*.gd"], cwd=root, capture_output=True, text=True, check=True)
    found = {}
    for path in files.stdout.split():
        if not path.startswith(SCANNED):
            continue
        n = count((root / path).read_text(encoding="utf-8", errors="replace"))
        if n:
            found[path] = n
    return found


def read_baseline(path: Path) -> tuple:
    entries, notes = {}, {}
    if not path.exists():
        return entries, notes
    for raw in path.read_text(encoding="utf-8").splitlines():
        line, _, note = raw.partition("#")
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit():
            entries[parts[1]] = int(parts[0])
            notes[parts[1]] = note.strip()
    return entries, notes


def compare(found: dict, baseline: dict) -> list:
    problems = []
    for path, n in sorted(found.items()):
        allowed = baseline.get(path)
        if allowed is None:
            problems.append(f"{path}: builds {n} node(s)/resource(s) in code; author a scene instead "
                            "(or mark the line procedural in the baseline with a reason)")
        elif n > allowed:
            problems.append(f"{path}: {n} > baseline {allowed}; move the new content into the scene")
        elif n < allowed:
            problems.append(f"{path}: {n} < baseline {allowed}; lower its line in the baseline")
    for path in sorted(set(baseline) - set(found)):
        problems.append(f"{path}: no longer builds content in code; remove its baseline line")
    return problems


def main(argv: list) -> int:
    found = scan(ROOT)
    baseline, notes = read_baseline(BASELINE)
    if "--write-baseline" in argv:
        lines = ["# Runtime construction baseline (RUNTIME_CONSTRUCTION_AUDIT.md): visual/physics/UI .new() per file.",
                 "# Checked by tools/ci/check_runtime_construction.py in `checks`. A line may only go down.",
                 "# Format: <count> <path>  # note ('procedural: why' when the construction is the procedure)."]
        for path, n in sorted(found.items()):
            note = notes.get(path, "")
            lines.append(f"{n} {path}" + (f"  # {note}" if note else ""))
        BASELINE.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"runtime construction: baseline written, {len(found)} file(s), {sum(found.values())} call(s)")
        return 0
    problems = compare(found, baseline)
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(f"runtime construction: {sum(found.values())} calls in {len(found)} files, none added")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
