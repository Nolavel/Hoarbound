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


class RibbonSplit(unittest.TestCase):
    def test_a_line_lands_in_every_chunk_it_crosses(self):
        from reality import editor_export, frame
        size = frame.chunk_size()
        xs = [10.0, size - 10.0, size + 10.0, 2 * size + 30.0, 2 * size + 60.0]
        mesh = {"kind": "ribbon", "width": 4.0, "parts": [{"p": [v for x in xs for v in (x, 5.0)], "y": [1.0, 2.0, 3.0, 4.0, 5.0]}]}
        pieces = editor_export._split_ribbon(mesh)
        self.assertEqual(sorted(pieces), ["0:0", "1:0", "2:0"])
        joined = sum(len(part["y"]) for piece in pieces.values() for part in piece["parts"])
        self.assertEqual(joined, 5 + 2, "each cut repeats its shared vertex once")
        self.assertEqual(pieces["2:0"]["parts"][0]["y"], [4.0, 5.0])


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


class Stems(unittest.TestCase):
    class _Surface:
        def ground_at(self, xy):
            import numpy as np
            return np.full(len(xy), 1.5)

        class dsm:
            @staticmethod
            def window(*_):
                return None

    class _Clear:
        def blocked(self, xy):
            from reality import frame
            return xy[:, 0] < frame.origin()[0] + 10.0  # a "road" covers local x < 10

    def test_stems_avoid_blocked_ground_and_repeat_exactly(self):
        import shapely
        from reality import vegetation, frame
        oe, on = frame.origin()
        area = shapely.box(oe, on - 40, oe + 40, on)
        cfg = {"density_per_100m2": {"scrub": 40.0}, "grid_m": 2.5, "low_vegetation_band_m": [0.3, 2.5],
               "bare_cell_share": 1.0, "max_clumps_per_feature": 10000}
        a = vegetation.stem_points(self._Surface(), self._Clear(), area, "scrub", "kw:test", cfg)
        b = vegetation.stem_points(self._Surface(), self._Clear(), area, "scrub", "kw:test", cfg)
        self.assertEqual(a, b, "same feature must give the same stems")
        self.assertGreater(len(a["y"]), 20)
        self.assertTrue(all(x >= 10.0 for x in a["p"][0::2]), "a stem stands on blocked ground")
        self.assertIsNone(vegetation.stem_points(self._Surface(), self._Clear(), area, "grass", "kw:test", cfg))

    def test_split_points_by_chunk(self):
        from reality import vegetation, frame
        size = frame.chunk_size()
        mesh = {"kind": "stems", "p": [1.0, 1.0, size + 1.0, 1.0], "y": [0.5, 0.6], "s": [1.0, 1.2], "lidar_low_vegetation_share": 0.0}
        pieces = vegetation.split_points(mesh)
        self.assertEqual(sorted(pieces), ["0:0", "1:0"])
        self.assertEqual(pieces["1:0"]["s"], [1.2])


class Drape(unittest.TestCase):
    class _Sunken:
        def ground_at(self, xy):
            import numpy as np
            from reality import frame
            oe, on = frame.origin()
            r = np.hypot(xy[:, 0] - (oe + 30.0), xy[:, 1] - (on - 30.0))
            return 2.0 - np.clip(1.0 - r / 20.0, 0.0, 1.0)  # rim 2.0 m, a lot sunk to 1.0 m in the middle

    def test_paving_follows_a_sunken_lot_instead_of_floating(self):
        import numpy as np
        from reality import frame, meshing
        oe, on = frame.origin()
        lot = shapely.box(oe, on - 60, oe + 60, on)
        mesh = meshing.drape(self._Sunken(), [lot])
        v = np.asarray(mesh["v"]).reshape(-1, 3)
        self.assertEqual(mesh["kind"], "drape")
        self.assertGreater(len(v), 100, "the interior needs grid vertices, not just the rim")
        ground = self._Sunken().ground_at(np.column_stack([v[:, 0] + oe, on - v[:, 2]]))
        self.assertLess(float(np.max(np.abs(v[:, 1] - ground - meshing.DRAPE_LIFT_M))), 0.011)
        self.assertLess(float(v[:, 1].min()), 1.2, "the paving does not reach down into the lot")


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


class EditLayer(unittest.TestCase):
    def test_check_rejects_bad_records_and_flags_stale_sources(self):
        from reality import edits
        hashes = {"kw:tree:a": "h1"}
        recs = [
            {"edit_id": "e1", "op": "remove", "layer": "base", "feature_id": "kw:tree:a", "source_geometry_hash": "h0"},
            {"edit_id": "e1", "op": "paint", "layer": "base", "feature_id": "kw:tree:a"},
            {"edit_id": "e3", "op": "remove", "layer": "summer", "feature_id": "kw:tree:missing"},
            {"edit_id": "e4", "op": "move", "layer": "winter", "feature_id": "kw:tree:a", "params": {"x": 1}},
        ]
        errors, warnings = edits.check(recs, hashes)
        text = " ".join(errors)
        for needle in ("repeated edit_id", "unknown op", "unknown layer", "not in the library", "needs params x and z"):
            self.assertIn(needle, text)
        self.assertTrue(any("changed in the source" in w for w in warnings))

    def test_only_base_changes_the_world_and_the_last_record_wins(self):
        from reality import edits
        recs = [{"edit_id": "a", "op": "move", "layer": "base", "feature_id": "f", "params": {"x": 0, "z": 0}},
                {"edit_id": "b", "op": "remove", "layer": "base", "feature_id": "f"},
                {"edit_id": "c", "op": "remove", "layer": "winter", "feature_id": "g", "chunk": "0:0", "_file": "x"}]
        self.assertEqual(edits.base_plan(recs)["f"]["edit_id"], "b")
        self.assertNotIn("g", edits.base_plan(recs))
        self.assertEqual([e["edit_id"] for e in edits.layered(recs)], ["c"])
        self.assertNotIn("_file", edits.layered(recs)[0])

    def test_move_lands_the_anchor_and_yaw_turns_east_towards_north(self):
        from reality import edits
        oe, on = frame.origin()
        stick = shapely.LineString([(oe, on), (oe + 10, on)])  # points east, anchor at its middle
        out = edits.moved(stick, {"params": {"x": 100.0, "z": 50.0, "yaw_deg": 90.0}})
        mid = out.interpolate(0.5, normalized=True)
        self.assertAlmostEqual(mid.x - oe, 100.0, places=6)
        self.assertAlmostEqual(on - mid.y, 50.0, places=6)
        (x0, y0), (x1, y1) = out.coords
        self.assertAlmostEqual(x1 - x0, 0.0, places=6)
        self.assertGreater(y1 - y0, 9.99, "a +90 yaw must turn east into north, as Godot rotation.y does")

    def test_load_takes_the_chunk_from_the_file_name(self):
        import json as js
        import tempfile
        from pathlib import Path as P
        from reality import edits
        with tempfile.TemporaryDirectory() as tmp:
            (P(tmp) / "edits_-7_3.json").write_text(js.dumps({"schema": edits.SCHEMA, "edits": [
                {"edit_id": "e", "op": "remove", "layer": "base", "feature_id": "f"}]}))
            recs = edits.load(P(tmp))
        self.assertEqual(recs[0]["chunk"], "-7:3")


class StaticSnow(unittest.TestCase):
    class _Wind:
        def __init__(self, upwind):
            import numpy as np
            self.upwind = np.asarray(upwind, float)

        def shelter(self, x, z):
            return 0.5

    def _cfg(self):
        from reality import static_snow
        return static_snow.settings()

    def test_slope_factor_follows_asce7_cold_roof(self):
        from reality import static_snow
        cfg = self._cfg()
        self.assertEqual(static_snow.slope_factor(20.0, cfg), 1.0)
        self.assertEqual(static_snow.slope_factor(45.0, cfg), 1.0)
        self.assertAlmostEqual(static_snow.slope_factor(57.5, cfg), 0.5)
        self.assertEqual(static_snow.slope_factor(75.0, cfg), 0.0)

    def _gable(self, pitch_deg):
        import math
        h = 5.0 * math.tan(math.radians(pitch_deg))
        # ridge along z at x = 0; west slope x in [-5, 0], east slope x in [0, 5]
        v = [-5, 3, 0, -5, 3, 10, 0, 3 + h, 0, 0, 3 + h, 10, 5, 3, 0, 5, 3, 10]
        i = [0, 1, 2, 2, 1, 3, 2, 3, 4, 4, 3, 5]
        return {"roof_v": v, "roof_i": i}

    def test_lee_slope_holds_more_than_windward(self):
        import numpy as np
        from reality import static_snow
        cap = static_snow.roof_cap(self._gable(30.0), self._Wind([1.0, 0.0]), self._cfg())  # wind from the east
        v = np.asarray(cap["v"]).reshape(-1, 3)
        top = v[: 6]  # the six roof vertices come first, lifted by their depth
        roof = np.asarray(self._gable(30.0)["roof_v"], float).reshape(-1, 3)
        lift = top[:, 1] - roof[[0, 1, 2, 3, 4, 5]][:, 1]
        self.assertGreater(lift[0], lift[4], "the west (lee) eave must hold more snow than the east (windward) one")
        self.assertGreater(len(cap["i"]) // 3, 4, "open edges need their eave lip")

    def test_steep_roof_sheds_its_snow(self):
        from reality import static_snow
        self.assertIsNone(static_snow.roof_cap(self._gable(75.0), self._Wind([1.0, 0.0]), self._cfg()))


if __name__ == "__main__":
    unittest.main()
