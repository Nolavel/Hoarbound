"""Unit tests for check_scene_refs.py on a throwaway git repo.
Run: python3 -m unittest discover -s tools/ci -p 'test_check_scene_refs.py'
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_scene_refs as csr  # noqa: E402


class SceneRefsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        self.write("a.gd", "extends Node\n")
        self.write("a.gd.uid", "uid://aaa\n")
        self.write("b.gd", "extends Node\n")
        self.write("b.gd.uid", "uid://bbb\n")

    def tearDown(self) -> None:
        self.dir.cleanup()

    def write(self, name: str, text: str) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def run_audit(self) -> list:
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        files = csr.tracked(self.root)
        by_uid, by_path, problems = csr.index(files, self.root)
        return problems + csr.audit(files, by_uid, by_path, self.root)

    def scene(self, ext: str) -> None:
        self.write("s.tscn", '[gd_scene format=3 uid="uid://sss"]\n\n' + ext + '\n\n[node name="S" type="Node"]\n')

    def kinds(self) -> list:
        return [p[0] for p in self.run_audit()]

    def test_clean_reference(self) -> None:
        self.scene('[ext_resource type="Script" uid="uid://aaa" path="res://a.gd" id="1"]')
        self.assertEqual(self.kinds(), [])

    def test_stale_uid_is_found_and_fixed(self) -> None:
        self.scene('[ext_resource type="Script" uid="uid://bbb" path="res://a.gd" id="1"]')
        problems = self.run_audit()
        self.assertEqual([p[0] for p in problems], ["stale_uid"])
        csr.fix(problems, self.root)
        self.assertIn('uid="uid://aaa" path="res://a.gd"', (self.root / "s.tscn").read_text())
        self.assertEqual(self.kinds(), [])

    def test_stale_path_resolves_by_uid(self) -> None:
        self.scene('[ext_resource type="Script" uid="uid://aaa" path="res://old/a.gd" id="1"]')
        problems = self.run_audit()
        self.assertEqual([p[0] for p in problems], ["stale_path"])
        csr.fix(problems, self.root)
        self.assertEqual(self.kinds(), [])

    def test_broken_reference(self) -> None:
        self.scene('[ext_resource type="Script" uid="uid://zzz" path="res://gone.gd" id="1"]')
        self.assertEqual(self.kinds(), ["broken"])

    def test_orphan_and_duplicate_uid(self) -> None:
        self.write("c.gd.uid", "uid://ccc\n")
        self.write("d.gd", "extends Node\n")
        self.write("d.gd.uid", "uid://aaa\n")
        self.assertEqual(sorted(self.kinds()), ["duplicate_uid", "orphan_uid"])

    def test_nested_project_is_skipped(self) -> None:
        self.write("docs/p/project.godot", "")
        self.write("docs/p/main.tscn", '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n')
        self.assertEqual(self.kinds(), [])


if __name__ == "__main__":
    unittest.main()
