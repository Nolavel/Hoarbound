"""Fails when two input actions share a key or button, unless the pair is in
tools/ci/input_overlap_allowlist.txt with the reason it is safe.
Run: python3 tools/ci/check_input_map.py"""
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ALLOWLIST = ROOT / "tools/ci/input_overlap_allowlist.txt"


def bindings():
    text = (ROOT / "project.godot").read_text()
    section = text.split("\n[input]\n", 1)[1].split("\n[", 1)[0]
    out = defaultdict(set)
    for action, body in re.findall(r"^\"?([\w ]+)\"?=\{(.*?)\n\}", section, re.S | re.M):
        for event in re.findall(r'Object\((InputEvent\w+),(.*?)"script":\s*null\s*\)', body, re.S):
            kind, props = event
            fields = dict(re.findall(r'"(\w+)":\s*([^,\n]+)', props))
            if kind == "InputEventKey":
                code = fields.get("physical_keycode", "0")
                code = code if code != "0" else fields.get("keycode", "0")
                mods = "".join(m[0] for m in ("shift_pressed", "ctrl_pressed", "alt_pressed")
                               if fields.get(m) == "true")
                out[f"key:{code}{'+' + mods if mods else ''}"].add(action.strip())
            elif kind == "InputEventMouseButton":
                out[f"mouse:{fields.get('button_index')}"].add(action.strip())
    return out


def allowed():
    pairs = set()
    if ALLOWLIST.exists():
        for line in ALLOWLIST.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                a, b = sorted(x.strip() for x in line.split(","))
                pairs.add((a, b))
    return pairs


def main():
    ok = allowed()
    bad = []
    for code, actions in sorted(bindings().items()):
        names = sorted(actions)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                if not a.startswith("ui_") or not b.startswith("ui_"):
                    if (a, b) not in ok:
                        bad.append(f"{code}: {a} <-> {b}")
    if bad:
        print("input map: undeclared overlaps (add to input_overlap_allowlist.txt with a reason, or rebind):")
        print("\n".join("  " + x for x in bad))
        sys.exit(1)
    print(f"input map: {len(bindings())} bindings, no undeclared overlaps")


main()
