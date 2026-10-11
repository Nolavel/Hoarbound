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


class DeckProfile(unittest.TestCase):
    def test_canopy_over_a_deck_does_not_lift_it_off_its_abutments(self):
        import numpy as np
        from rasterio.transform import from_origin
        from reality import meshing

        class Fake:
            def ground_at(self, xy):
                return np.zeros(len(xy))

            def dsm_window(self, geom, pad=1.0):
                grid = np.full((200, 200), 10.0)  # canopy everywhere, 10 m up
                return grid, np.ones_like(grid, bool), from_origin(-10.0, 90.0, 0.5, 0.5)

        line = shapely.LineString([(0, 40), (40, 40)])
        xy, ys, src = meshing.deck_profile(Fake(), line, abutments=True)
        d = np.hypot(xy[:, 0] - xy[0, 0], xy[:, 1] - xy[0, 1])
        cap = np.minimum(d, d[-1] - d) * meshing.DECK_RAMP_MAX + 0.05
        self.assertTrue(np.all(np.asarray(ys) <= cap + 1e-6), "deck rose faster than 1:8 from an abutment")
        self.assertAlmostEqual(ys[0], 0.05)
        self.assertIn("abutments", src)


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
            landmarks._write_glb(out, [{"name": "T-col", "surfaces": [dict(tri, material="fort_brick")]}], "test")
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


class Shelter727(unittest.TestCase):
    def test_plan_frame_round_trips_and_matches_godot_yaw(self):
        import math
        import numpy as np
        import shapely.affinity
        from reality import frame as fr, shelter_727
        oe, on = fr.origin()
        x0, z0 = -3500.0, 1500.0
        box = shapely.affinity.rotate(shapely.box(-14, -7, 14, 3), 33.0, origin=(0, 0))
        local = shapely.affinity.translate(box.union(shapely.box(-5, 2, 4, 10)), x0, z0)
        proj = shapely.transform(local, lambda c: np.column_stack([c[:, 0] + oe, on - c[:, 1]]))
        plan = shelter_727.Plan(proj, [x0, 0.0, z0])
        self.assertGreater(plan.walls.bounds[3], -plan.walls.bounds[1], "wing must land on +v")
        x, z = plan.to_local_xz(5.0, 2.0)
        back = plan.to_projected(shapely.Point(5.0, 2.0))
        self.assertAlmostEqual(back.x - oe - x0, x, places=6)
        self.assertAlmostEqual(on - back.y - z0, z, places=6)
        a = plan.godot_yaw()  # Godot Basis(UP, a) * (u, 0, v): x = u cos a + v sin a, z = -u sin a + v cos a
        self.assertAlmostEqual(5.0 * math.cos(a) + 2.0 * math.sin(a), x, places=6)
        self.assertAlmostEqual(-5.0 * math.sin(a) + 2.0 * math.cos(a), z, places=6)

    def test_openings_follow_the_hut_standard(self):
        from reality import shelter_727
        self.assertEqual(shelter_727._opening_y("door", 0.5), (0.5, 2.75))
        y0, y1 = shelter_727._opening_y("window", 0.5)
        self.assertAlmostEqual(y1 - y0, 1.1)
        self.assertAlmostEqual(y0 - 0.5, 0.8)
        door = next(o for o in shelter_727.OPENINGS if o[0] == "MainDoor")
        r = shelter_727._opening_rect(door)
        self.assertAlmostEqual(r.bounds[2] - r.bounds[0], 1.5)


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
