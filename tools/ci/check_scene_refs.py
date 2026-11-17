#!/usr/bin/env python3
"""Scene audit + UID doctor: broken or stale references in .tscn/.tres, without Godot.

Indexes every resource's UID (.uid sidecars, .import remaps, scene/resource headers) and checks each
ext_resource line:
  broken     neither the path nor the uid resolves: the scene will fail to load
  stale_uid  the path exists but carries another uid: Godot warns and falls back to the path
  stale_path the uid resolves but the path moved: works by uid, misleads people and tools
Also reports duplicate uids and orphaned .uid sidecars. Report only by default; --fix rewrites
stale_uid and stale_path lines when the answer is unambiguous. Known debt lives in
tools/ci/scene_refs_baseline.txt; anything new fails.
Run: python3 tools/ci/check_scene_refs.py [--fix] [--write-baseline]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "tools/ci/scene_refs_baseline.txt"
SKIPPED = ("archive/", ".godot/")
HEADER_UID = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[a-z0-9]+)"')
IMPORT_UID = re.compile(r'^uid="(uid://[a-z0-9]+)"', re.M)
EXT = re.compile(r'^\[ext_resource\b[^\]]*\]', re.M)
ATTR = re.compile(r'(\w+)="([^"]*)"')


def tracked(root: Path = ROOT) -> list:
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split("\n")
    files = [p for p in out if p and not p.startswith(SKIPPED)]
    ## Nested Godot projects (previews under docs/) have their own res:// root.
    nested = [p[: -len("project.godot")] for p in files if p.endswith("/project.godot")]
    return [p for p in files if not any(p.startswith(n) for n in nested)]


def res(path: str) -> str:
    return "res://" + path


def index(files: list, root: Path = ROOT) -> tuple:
    by_uid, by_path, problems = {}, {}, []
    present = set(files)

    def add(uid: str, path: str, source: str) -> None:
        if uid in by_uid and by_uid[uid] != path:
            problems.append(("duplicate_uid", source, f"{uid} names both {by_uid[uid]} and {path}"))
            return
        by_uid[uid] = path
        by_path[path] = uid

    for f in files:
        full = root / f
        if f.endswith(".uid"):
            target = f[:-4]
            if target not in present:
                problems.append(("orphan_uid", f, f"sidecar for missing {target}"))
                continue
            add(full.read_text(encoding="utf-8", errors="replace").strip(), res(target), f)
        elif f.endswith(".import"):
            match = IMPORT_UID.search(full.read_text(encoding="utf-8", errors="replace"))
            if match:
                add(match.group(1), res(f[:-7]), f)
        elif f.endswith((".tscn", ".tres")):
            with open(full, encoding="utf-8", errors="replace") as handle:
                match = HEADER_UID.match(handle.readline())
            if match:
                add(match.group(1), res(f), f)
    return by_uid, by_path, problems


def audit(files: list, by_uid: dict, by_path: dict, root: Path = ROOT) -> list:
    problems = []
    on_disk = {res(f) for f in files}
    for f in files:
        if not f.endswith((".tscn", ".tres")):
            continue
        text = (root / f).read_text(encoding="utf-8", errors="replace")
        for line in EXT.findall(text):
            attrs = dict(ATTR.findall(line))
            path, uid = attrs.get("path", ""), attrs.get("uid", "")
            if not path:
                continue
            path_ok = path in on_disk
            uid_path = by_uid.get(uid) if uid else None
            if not path_ok and uid_path is None:
                problems.append(("broken", f, f"{path} ({uid or 'no uid'})"))
            elif not path_ok:
                problems.append(("stale_path", f, f"{path} -> {uid_path}"))
            elif uid and uid_path != path:
                right = by_path.get(path)
                problems.append(("stale_uid", f, f"{path} has {uid}, expected {right or 'none'}"))
    return problems


def fix(problems: list, root: Path = ROOT) -> int:
    fixed = 0
    for kind, f, detail in problems:
        full = root / f
        text = full.read_text(encoding="utf-8")
        if kind == "stale_uid":
            path, _, rest = detail.partition(" has ")
            wrong, _, right = rest.partition(", expected ")
            if right == "none":
                continue
            new = text.replace(f'uid="{wrong}" path="{path}"', f'uid="{right}" path="{path}"')
        elif kind == "stale_path":
            old, _, new_path = detail.partition(" -> ")
            new = text.replace(f'path="{old}"', f'path="{new_path}"')
        else:
            continue
        if new != text:
            full.write_text(new, encoding="utf-8")
            fixed += 1
    return fixed


def key(problem: tuple) -> str:
    return f"{problem[0]} {problem[1]} :: {problem[2]}"


def main(argv: list) -> int:
    files = tracked()
    by_uid, by_path, problems = index(files)
    problems += audit(files, by_uid, by_path)
    if "--fix" in argv:
        print(f"scene refs: fixed {fix(problems)} line(s); re-run to confirm")
        return 0
    lines = sorted(key(p) for p in problems)
    if "--write-baseline" in argv:
        BASELINE.write_text("# Known scene-reference debt; may only shrink. Written by check_scene_refs.py --write-baseline.\n"
                            + "".join(line + "\n" for line in lines), encoding="utf-8")
        print(f"scene refs: baseline written with {len(lines)} entr(ies)")
        return 0
    known = set()
    if BASELINE.exists():
        known = {l.strip() for l in BASELINE.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")}
    new = [l for l in lines if l not in known]
    gone = sorted(known - set(lines))
    for l in new:
        print("NEW  " + l)
    for l in gone:
        print("GONE " + l + "   (remove it from the baseline)")
    if new or gone:
        print(f"scene refs: {len(new)} new, {len(gone)} fixed but still in the baseline")
        return 1
    print(f"scene refs: clean ({len(lines)} known in baseline)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
