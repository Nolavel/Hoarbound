"""Unit tests for the parts of the pipeline that must never regress (no network, no raw cache).

python3 -m unittest tools/world/reality/test_reality.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import shapely  # noqa: E402

from reality import frame, ids, library, regen  # noqa: E402
from reality.model import geometry_hash  # noqa: E402


class RegenGuard(unittest.TestCase):
    def test_locked_asset_is_never_regenerated(self):
        assets = [{"feature_id": "kw:building:osm:w1", "authoring_state": "artist_locked", "source_geometry_hash": "aaa", "last_generator_version": "0"},
                  {"feature_id": "kw:building:osm:w2", "authoring_state": "artist_modified", "source_geometry_hash": "bbb", "last_generator_version": "1"},
                  {"feature_id": "kw:building:osm:w3", "authoring_state": "generated", "source_geometry_hash": "ccc", "last_generator_version": "1"},
                  {"feature_id": "kw:building:osm:w9", "authoring_state": "artist_locked", "source_geometry_hash": "zzz"}]
        current = {"kw:building:osm:w1": "aaa-changed", "kw:building:osm:w2": "bbb", "kw:building:osm:w3": "ccc-changed", "kw:building:osm:w4": "ddd"}
        p = regen.plan(current, assets, "1")
        self.assertEqual(p["kw:building:osm:w1"]["action"], "needs_rebase")
        self.assertEqual(p["kw:building:osm:w2"]["action"], "keep_locked")
        self.assertEqual(p["kw:building:osm:w3"]["action"], "regenerate")
        self.assertEqual(p["kw:building:osm:w4"]["action"], "generate")
        self.assertEqual(p["kw:building:osm:w9"]["action"], "orphaned")
        self.assertEqual(regen.violations(p), [])

    def test_violation_detector(self):
        bad = {"x": {"action": "regenerate", "asset": {"authoring_state": "artist_locked"}}}
        self.assertTrue(regen.violations(bad))


class Identity(unittest.TestCase):
    def test_osm_key_drops_version(self):
        self.assertEqual(ids.osm_key("w462887766@12"), "w462887766")
        self.assertEqual(ids.make("buildings", "osm", "w1"), "kw:building:osm:w1")

    def test_collision_falls_back(self):
        reg = ids.IdRegistry()
        a = reg.claim("kw:building:osm:w1", "kw:building:overture:x")
        b = reg.claim("kw:building:osm:w1", "kw:building:overture:y")
        self.assertNotEqual(a, b)
        self.assertEqual(b, "kw:building:overture:y")

    def test_identity_map_carries_ids(self):
        reg = ids.IdRegistry({("src", "rec"): "kw:building:osm:w1"})
        self.assertEqual(reg.claim("kw:building:overture:new", "kw:building:overture:new", ("src", "rec")), "kw:building:osm:w1")

    def test_node_name_is_engine_safe(self):
        self.assertEqual(library.node_name("kw:building:osm:w123"), "KW_BUILDING_osm_w123")
        self.assertNotIn(":", library.node_name("kw:tree:lidar2019:E1.0N2.0"))


class Frame(unittest.TestCase):
    def test_local_origin_matches_runtime_crop(self):
        self.assertEqual(frame.projected_to_local(422025.0, 2717003.0), (0.0, 0.0))
        self.assertEqual(frame.projected_to_local(415424.0, 2720288.0), (-6601.0, -3285.0))
        self.assertEqual(frame.chunk_of_local(-0.1, 0.1), "-1:0")

    def test_geometry_hash_ignores_sub_cm_noise(self):
        a = shapely.Polygon([(0, 0), (10, 0), (10, 10), (0, 10)])
        b = shapely.Polygon([(0.001, 0), (10, 0), (10, 10.002), (0, 10)])
        self.assertEqual(geometry_hash(a), geometry_hash(b))
        self.assertNotEqual(geometry_hash(a), geometry_hash(shapely.Polygon([(0, 0), (10.5, 0), (10, 10), (0, 10)])))


class DemVoids(unittest.TestCase):
    def test_void_never_surfaces_as_land(self):
        import numpy as np
        from reality import meshing
        dem = np.array([[2.0, 2.0, np.nan], [-3.0, np.nan, np.nan], [-3.0, -3.0, np.nan]], np.float32)
        filled, void = meshing.fill_dem_voids(dem, -0.538)
        self.assertTrue(np.isfinite(filled).all())
        self.assertTrue((filled[void] <= -0.538).all())
        self.assertEqual(filled[0, 0], 2.0)


class Landmarks(unittest.TestCase):
    def test_inset_reproduces_documented_floor_area(self):
        from reality import landmarks
        sq = shapely.Polygon([(0, 0), (20, 0), (20, 10), (0, 10)])
        d = landmarks._inset_for_area(sq, 19 * 9)
        self.assertAlmostEqual(d, 0.5, places=3)

    def test_glb_is_valid_gltf_binary(self):
        import json as _json
        import struct
        import tempfile
        import numpy as np
        from pathlib import Path as P
        from reality import landmarks
        tri = landmarks._mesh([np.array([[0, 0, 0], [1, 0, 0], [0, 0, -1]], float)])
        with tempfile.TemporaryDirectory() as tmp:
            out = P(tmp) / "t.glb"
            landmarks._write_glb(out, [{"name": "T-col", "surfaces": [dict(tri, material="fort_brick")]}])
            data = out.read_bytes()
        magic, version, length = struct.unpack("<4sII", data[:12])
        self.assertEqual((magic, version, length), (b"glTF", 2, len(data)))
        jlen, jtype = struct.unpack("<I4s", data[12:20])
        doc = _json.loads(data[20:20 + jlen])
        self.assertEqual(jtype, b"JSON")
        self.assertEqual(doc["nodes"][0]["name"], "T-col")
        self.assertEqual(doc["accessors"][0]["count"], 3)
        self.assertEqual(len(data) % 4, 0)

    def test_artist_owned_landmark_is_never_rewritten(self):
        import json as _json
        import tempfile
        from pathlib import Path as P
        from unittest import mock
        from reality import landmarks
        with tempfile.TemporaryDirectory() as tmp:
            man = P(tmp) / "asset_manifest.json"
            man.write_text(_json.dumps({"assets": [{"feature_id": "kw:building:osm:w1", "authoring_state": "artist_locked"}]}))
            with mock.patch.object(landmarks, "MANIFEST", man):
                self.assertFalse(landmarks._may_write("kw:building:osm:w1"))
                self.assertTrue(landmarks._may_write("kw:building:osm:w2"))


class LibraryUnpack(unittest.TestCase):
    def test_existing_working_copy_is_never_overwritten(self):
        import tempfile
        from pathlib import Path as P
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            lib = P(tmp) / "lib.gpkg"
            lib.write_bytes(b"fresh build")
            man = P(tmp) / "manifest.json"
            man.write_text('{"gpkg": {"bytes": 1, "sha256": "x"}}')
            with mock.patch.object(library.paths, "LIBRARY", lib), mock.patch.object(library, "MANIFEST", man):
                library.ensure()
            self.assertEqual(lib.read_bytes(), b"fresh build")


if __name__ == "__main__":
    unittest.main()
