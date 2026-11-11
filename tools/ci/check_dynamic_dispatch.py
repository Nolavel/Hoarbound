#!/usr/bin/env python3
"""Ratchet on dynamic dispatch in game code (ARCHITECTURE.md §16).

Counts has_method( and string .call("...") / .call(&"...") per tracked .gd file outside the boundary and
tool folders, and compares each file with tools/ci/dynamic_dispatch_baseline.txt. A file may not exceed its
baseline, a new file may not start using them, and a file that dropped below its baseline must have its line
lowered (so the debt only shrinks). Every baseline line names its class A-F from §16.
Run: python3 tools/ci/check_dynamic_dispatch.py   (exit 1 on a violation)
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "tools/ci/dynamic_dispatch_baseline.txt"
SKIPPED = ("core/contracts/", "tests/", "tools/", "addons/", "archive/")
CLASSES = set("ABCDEF")
PATTERN = re.compile(r'has_method\(|\.call\(\s*&?"')


def count(text: str) -> int:
    total = 0
    for line in text.splitlines():
        code = line.split("#", 1)[0]
        total += len(PATTERN.findall(code))
    return total


def scan(root: Path) -> dict:
    files = subprocess.run(["git", "ls-files", "*.gd"], cwd=root, capture_output=True, text=True, check=True)
    found = {}
    for path in files.stdout.split():
        if path.startswith(SKIPPED):
            continue
        n = count((root / path).read_text(encoding="utf-8", errors="replace"))
        if n:
            found[path] = n
    return found


def read_baseline(path: Path) -> tuple:
    entries, errors = {}, []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 3 or not parts[0].isdigit() or parts[1] not in CLASSES:
            errors.append(f"baseline line {number}: expected '<count> <class A-F> <path>', got: {raw.strip()}")
            continue
        entries[parts[2]] = int(parts[0])
    return entries, errors


def compare(found: dict, baseline: dict) -> list:
    problems = []
    for path, n in sorted(found.items()):
        allowed = baseline.get(path)
        if allowed is None:
            problems.append(f"{path}: {n} new dynamic call(s); use a typed reference, a signal or a capability (§16)")
        elif n > allowed:
            problems.append(f"{path}: {n} dynamic calls, baseline {allowed}; the debt may only shrink (§16)")
        elif n < allowed:
            problems.append(f"{path}: {n} dynamic calls, baseline {allowed}; lower its line in {BASELINE.name}")
    for path, allowed in sorted(baseline.items()):
        if path not in found:
            problems.append(f"{path}: no dynamic calls left (baseline {allowed}); remove its line from {BASELINE.name}")
    return problems


def main() -> int:
    baseline, errors = read_baseline(BASELINE)
    problems = errors + compare(scan(ROOT), baseline)
    for problem in problems:
        print(f"dynamic dispatch: {problem}")
    if problems:
        return 1
    print(f"dynamic dispatch: {sum(baseline.values())} calls in {len(baseline)} files, none added")
    return 0


if __name__ == "__main__":
    sys.exit(main())
