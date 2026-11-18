"""Unit tests for the parts of the pipeline that must never regress (no network, no raw cache).

python3 -m unittest tools/world/reality/test_reality.py
"""
from __future__ import annotations

import json
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

    def _layout(self):
        from reality import shelter_727
        return shelter_727.Layout(-13.24, 4.16)

    def test_drawing_outline_matches_the_city_record_area(self):
        self.assertAlmostEqual(self._layout().outline().area, 343.1, delta=343.1 * 0.01)  # 3,693 sq ft

    def test_fit_recovers_a_shifted_outline(self):
        import shapely.affinity
        from reality import shelter_727
        target = shapely.affinity.translate(shelter_727.Layout(-13.0, 4.0).outline(), 0.0, 0.0)
        fit = shelter_727.fit_layout(target)
        self.assertAlmostEqual(fit.a, -13.0, places=1)
        self.assertAlmostEqual(fit.front, 4.0, places=1)

    def test_main_door_is_the_permit_entrance(self):
        from reality import shelter_727
        lay = self._layout()
        door = shelter_727.opening("MainDoor", lay)
        self.assertEqual((door.axis, door.outward, door.room), ("u", (-1, 0), "waiting"))
        sw = 8 * 0.3048  # A2.01 NW: 8'-0" x 8'-0" double storefront, centre 2.78 m past the main front
        fixed = shelter_727.opening("EntranceFixedLeaf", lay)
        self.assertAlmostEqual(door.along, lay.front + 2.78 + sw / 4, places=2)  # the opening leaf is the Fort Street one
        self.assertAlmostEqual(fixed.along, lay.front + 2.78 - sw / 4, places=2)
        self.assertAlmostEqual(door.width + fixed.width, sw, places=3)
        self.assertEqual((door.height, fixed.height, fixed.kind, fixed.room), (sw, sw, "window", "waiting"))
        self.assertEqual(shelter_727._opening_y(fixed, 0.66), (0.66, 0.66 + sw))

    def test_windows_follow_the_2020_elevations(self):
        from reality import shelter_727
        lay = self._layout()
        windows = [o for o in shelter_727.openings(lay) if o.kind == "window" and o.name != "EntranceFixedLeaf"]
        by_room = {}
        for w in windows:
            by_room.setdefault(w.room, []).append(w.name)
            self.assertAlmostEqual(w.y0, 1.06, places=2)  # sill and head over ground, A2.01
            self.assertAlmostEqual(w.y1, 2.60, places=2)
        self.assertEqual(sorted(by_room["waiting"]), ["FrontWindow1", "FrontWindow2", "FrontWindow3", "SideWindowEast"])
        self.assertEqual(len(by_room["lobby"]), 3)
        self.assertNotIn("dental", by_room, "the back elevation has no windows")
        self.assertAlmostEqual(next(w for w in windows if w.name == "FrontWindow1").width, 2.46, places=2)

    def test_wall_thermometer_hangs_in_the_heated_room(self):
        from reality import shelter_727
        lay = shelter_727.Layout(-13.24, 4.16)
        t = next(f for f in shelter_727.furniture(lay) if f["kind"] == "wall_thermometer")
        self.assertEqual((t["room"], t["h"]), ("waiting", 1.7))

    def test_rooms_furniture_and_openings_fit_the_new_walls(self):
        import shapely
        from reality import shelter_727
        lay = self._layout()
        inner = lay.outline().buffer(-shelter_727.WALL_T, join_style="mitre")
        rooms = dict((rid, shapely.box(*r)) for rid, _, r in shelter_727.rooms(lay))
        for rid, box in rooms.items():
            self.assertGreater(box.intersection(inner).area / box.area, 0.97, rid)
        for f in shelter_727.furniture(lay):
            self.assertTrue(rooms[f["room"]].buffer(0.01).contains(shapely.Point(f["uv"])), f["node"])
        shell = lay.outline().difference(inner)
        for o in shelter_727.openings(lay):
            if o.kind in ("door", "window"):
                self.assertTrue(shelter_727._opening_rect(o).intersects(shell), o.name)


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


class DocumentedBuildings(unittest.TestCase):
    """Lofts at Bahama Village from Legistar 22-3575: the record's numbers pin the georeference."""

    FORT_CROSSING = (418468.23, 2715428.26)  # OSM node 5577506219, Fort St x Allen Ave
    FORT_TO_PETRONIA = (418494.04, 2715391.98)  # OSM node 3239061938

    def _features(self):
        from reality import documented
        return [f for f in documented.features(ids.IdRegistry()) if ":legistar_22_3575_" in f.feature_id]

    def test_lofts_area_matches_record(self):
        area_sqft = sum(f.geom.area for f in self._features()) / 0.3048 ** 2
        self.assertAlmostEqual(area_sqft, 52870, delta=52870 * 0.06)

    def test_fort_facades_sit_behind_the_right_of_way(self):
        fort = shapely.LineString([self.FORT_CROSSING, self.FORT_TO_PETRONIA])
        fort = shapely.affinity.scale(fort, 6.0, 6.0)  # the centreline beyond both nodes
        for f in self._features():
            if f.feature_id.endswith(("_a_fort", "_c_south", "_c_north")):
                self.assertTrue(4.5 <= f.geom.distance(fort) <= 7.5, f"{f.feature_id}: {f.geom.distance(fort):.2f} m")

    def test_lofts_stand_across_fort_street_from_727(self):
        import numpy as np
        a, b = np.asarray(self.FORT_CROSSING), np.asarray(self.FORT_TO_PETRONIA)

        def side(p) -> float:
            d, q = b - a, np.asarray(p) - a
            return float(np.sign(d[0] * q[1] - d[1] * q[0]))
        shelter = (418493.22, 2715412.72)  # 727 Fort St centroid, east of Fort St
        for f in self._features():
            self.assertEqual(side(f.geom.centroid.coords[0]), -side(shelter), f.feature_id)

    def test_records_carry_provenance(self):
        feats = self._features()
        self.assertEqual(len(feats), 5)
        for f in feats:
            self.assertTrue(f.feature_id.startswith("kw:building:doc:legistar_22_3575_"))
            self.assertEqual((f.geometry_source, f.geometry_method, f.geometry_recon), ("city_kw_legistar_22_3575", "approved_site_plan_georeferenced", "derived"))
            self.assertEqual((f.geometry_confidence, f.geometry_accuracy_m, f.valid_from), (0.6, 2.0, "2025-10-30"))
            self.assertEqual(f.source_epoch, "2022-12-19", "the node contract needs the plan's epoch")
            self.assertIn("as_designed_not_surveyed", f.flags)
            self.assertIn("Legistar 22-3575", f.geometry_record)
            roof = f.selected("roof_documented").value
            self.assertLess(roof["eave_m"], roof["top_m"])
            self.assertLessEqual(roof["top_m"], 10.67 - 0.36 + 1e-6)  # 35 ft over the crown, stored above the sidewalk


class DocumentedDouglass(unittest.TestCase):
    """Frederick Douglass Community Center and Gym from Legistar 21-7769 (sheet A1.1.1, 1 in = 10 ft)."""

    FORT_OLIVIA = (418562.45, 2715290.52)  # OSM node 99079687
    CITY_5038_EAST = (418636.97, 2715346.79)  # east-most vertex, City of Key West footprint OBJECTID 5038 (2017)

    def _features(self):
        from reality import documented
        return {f.feature_id.rsplit("_21_7769_", 1)[1]: f for f in documented.features(ids.IdRegistry()) if ":legistar_21_7769_" in f.feature_id}

    def test_centre_floor_area_matches_record(self):
        f = self._features()
        area_sqft = (f["centre_low"].geom.area + f["centre_hall"].geom.area) / 0.3048 ** 2
        self.assertAlmostEqual(area_sqft, 9587, delta=9587 * 0.08)

    def test_georeference_agrees_with_the_city_footprint(self):
        import numpy as np
        from reality import documented
        georef = [b for b in documented.load()["buildings"] if b["key"] == "legistar_21_7769"][0]["georef"]
        survey_line = np.asarray(documented.georeference([[5074.0, 1343.0], [5074.0, 3195.0], [5075.0, 3195.0]], georef).exterior.coords)[0]
        city_east = np.array(self.CITY_5038_EAST)
        along_olivia = np.asarray(georef["right_axis_en"], float)
        self.assertLess(abs(float((city_east - survey_line) @ along_olivia)), 0.5, "sheet x 5074 is the surveyed east face 2.15 ft off Emma St")

    def test_existing_gym_is_left_to_lidar(self):
        from reality import documented
        f = self._features()
        self.assertEqual(sorted(k for k, v in f.items() if v.feature_id in documented.lidar_masses(list(f.values()))), ["gym", "gym_west"])
        self.assertIsNone(f["gym"].selected("height_m"))
        self.assertIn("existing_per_site_plan", f["gym"].flags)
        self.assertNotIn("as_designed_not_surveyed", f["gym"].flags)

    def test_old_merged_outline_is_superseded(self):
        from reality import documented
        s = {e["feature_id"]: e for e in documented.supersessions()}
        self.assertEqual(s["kw:building:osm:w339414847"]["valid_to"], "2023-09-18")


class ExportWorldDate(unittest.TestCase):
    """The world is built as it stood on the world date: later buildings and demolished ones stay out."""

    def test_in_world(self):
        from reality import editor_export
        self.assertTrue(editor_export.in_world("2025-10-30", None, "2025-12-31"))
        self.assertTrue(editor_export.in_world(None, None, "2025-12-31"))
        self.assertFalse(editor_export.in_world(None, "2023-09-18", "2025-12-31"))
        self.assertFalse(editor_export.in_world("2026-02-01", None, "2025-12-31"))
        self.assertTrue(editor_export.in_world("1948", None, "2025-12-31"))


class WaysOnWorldDate(unittest.TestCase):
    """A way that no longer exists on the world date (a demolished parking aisle) removes no building."""

    def test_closed_way_does_not_remove_a_building(self):
        from unittest import mock
        from reality import traversal
        building = shapely.box(0.0, 0.0, 20.0, 20.0)
        aisle = shapely.LineString([(-5.0, 10.0), (25.0, 10.0)])
        layers = {"buildings": ([building], {"feature_id": ["kw:building:doc:x"], "valid_from": [None], "valid_to": [None]}),
                  "roads": ([aisle], {"feature_id": ["kw:road:x"], "class": ["service"], "attrs_json": ["{}"],
                                      "valid_from": [None], "valid_to": [None]})}
        with mock.patch.object(traversal.library, "read_layer", lambda fam: layers[fam]):
            self.assertEqual(traversal.buildings_on_ways(set()), {"kw:building:doc:x": ["kw:road:x"]})
            layers["roads"][1]["valid_to"][0] = "2023-09-18"
            self.assertEqual(traversal.buildings_on_ways(set()), {})


class CityFootprints(unittest.TestCase):
    """City of Key West footprints: only owner-reviewed decisions reach the library."""

    def _decisions(self):
        return {"source_id": "city_of_key_west_gis", "observed_at": "2017-11-06",
                "accept": {"1": {"evidence": "test"}, "2": {"evidence": "test"}},
                "split": {"kw:building:osm:w9": {"into": ["1", "2"], "reason": "two houses in one outline"}},
                "hashes": {}}

    def _records(self):
        a = shapely.box(418000.0, 2715000.0, 418010.0, 2715010.0)
        b = shapely.box(418012.0, 2715000.0, 418022.0, 2715010.0)
        c = shapely.box(418040.0, 2715000.0, 418050.0, 2715010.0)
        return {"1": a, "2": b, "3": c}

    def test_only_accepted_records_become_features(self):
        from reality import city_footprints
        feats = city_footprints.features(ids.IdRegistry(), self._records(), self._decisions())
        self.assertEqual(sorted(f.feature_id for f in feats), ["kw:building:citykw:1", "kw:building:citykw:2"])
        f = feats[0]
        self.assertEqual((f.geometry_source, f.geometry_method, f.observed_at), ("city_of_key_west_gis", "official_footprint", "2017-11-06"))

    def test_changed_source_record_is_refused(self):
        from reality import city_footprints
        from reality.model import geometry_hash
        d = self._decisions()
        d["hashes"] = {"1": geometry_hash(self._records()["1"]), "2": "changed"}
        with self.assertRaises(SystemExit):
            city_footprints.features(ids.IdRegistry(), self._records(), d)

    def test_split_removes_the_merged_outline_and_records_why(self):
        import sqlite3
        import tempfile
        from reality import build, city_footprints
        from reality.model import Feature
        merged = Feature("kw:building:osm:w9", "buildings", "building", shapely.box(417999.0, 2714999.0, 418023.0, 2715011.0),
                         "overture_2026_09_23_1", "w9", "identity", "derived", 0.8)
        build.chunk_and_local([merged])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "lib.gpkg"
            library.write_layer(path, "buildings", [merged], append=False)
            library._write_tables(path, [merged], [], {"features": [], "assets": []}, {"schema_version": "test"})
            removed = library.remove_features(path, city_footprints.removals(self._decisions()))
            self.assertEqual(removed, ["kw:building:osm:w9"])
            _, cols = library.read_layer("buildings", path)
            self.assertEqual(list(cols["feature_id"]), [])
            con = sqlite3.connect(path)
            reason = con.execute("SELECT reason FROM excluded WHERE source_record_id = 'kw:building:osm:w9'").fetchone()[0]
            con.close()
            self.assertIn("citykw:1", reason)


class Shelter727Sockets(unittest.TestCase):
    """First Exit pickups in and beside 727 sit in their rooms, on their furniture, and clear of the entrance."""

    def _spec(self):
        return json.loads((Path(__file__).resolve().parents[3] / "data/world/key_west/reality/landmarks/kw_727_fort_st.json").read_text())

    def test_every_raised_socket_rests_on_furniture(self):
        from reality import first_exit_sites
        sockets = first_exit_sites._shelter_sockets(self._spec()["interior"])
        for name, s in sockets.items():
            if s["h"] > 0.0:
                self.assertIsNotNone(s["on"], f"{name} floats {s['h']} m over the floor")
        cabinet = next(f for f in self._spec()["interior"]["furniture"] if f["node"] == "Cabinet")
        for name in ("GlovesShelter", "SPoVCanShelter"):
            self.assertEqual((sockets[name]["on"], sockets[name]["uv"]), ("Cabinet", cabinet["uv"]), name)

    def test_floating_socket_is_refused(self):
        from reality import first_exit_sites
        spec = self._spec()
        saved = dict(first_exit_sites.SHELTER_SOCKETS)
        try:
            first_exit_sites.SHELTER_SOCKETS = {"Probe": ("storage", 9.0, -4.5, 0.80, 0)}
            with self.assertRaises(SystemExit):
                first_exit_sites._shelter_sockets(spec["interior"])
        finally:
            first_exit_sites.SHELTER_SOCKETS = saved

    def test_yard_is_outside_beside_the_ramp_and_off_the_walk(self):
        from reality import facade_727, first_exit_sites
        spec = self._spec()
        walls = shapely.Polygon(spec["interior"]["outline_uv"])
        ramp = spec["interior"]["entry_ramp"]
        walk = shapely.LineString([ramp["from_uv"], ramp["to_uv"]]).buffer(0.75, cap_style="flat")
        planters = [shapely.box(p["box"][0][0], p["box"][0][2], p["box"][1][0], p["box"][1][2])
                    for p in facade_727.parts(spec, walls) if p["name"].startswith("Planter")]
        for name, uv in first_exit_sites.SHELTER_YARD.items():
            spot = shapely.Point(uv).buffer(0.3)
            self.assertFalse(spot.intersects(walls), name)
            self.assertFalse(spot.intersects(walk), name)
            self.assertFalse(any(spot.intersects(p) for p in planters), name)
            self.assertLess(shapely.Point(uv).distance(walk), 2.0, f"{name} is not beside the ramp")


class Facade727(unittest.TestCase):
    """727 Fort St exterior after the 2020 permit set (A2.01 elevations, A1.03 plan) on the permit outline."""

    def _parts(self):
        from reality import facade_727
        spec = json.loads((Path(__file__).resolve().parents[3] / "data/world/key_west/reality/landmarks/kw_727_fort_st.json").read_text())
        roof = shapely.Polygon(spec["interior"]["outline_uv"])
        return {p["name"]: p for p in facade_727.parts(spec, roof)}, spec

    def test_canopy_follows_the_permit_set(self):
        parts, spec = self._parts()
        g = spec["interior"]["layout"]["faces"]
        front = parts["CanopyFront"]
        self.assertAlmostEqual(front["box"][0][1], 3.2, places=2)  # underside 10'-6" over ground (A2.01)
        self.assertAlmostEqual(front["box"][1][2] - g["P"], 5 * 0.3048, places=2)  # 5 ft past the wing front (A1.03)
        self.assertAlmostEqual(front["box"][0][0], g["PW"] - 4.9 * 0.3048, places=2)
        self.assertAlmostEqual(front["box"][1][0], g["PE"] + 4.9 * 0.3048, places=2)

    def test_parapet_tops_at_16_ft_2_in(self):
        parts, _ = self._parts()
        self.assertAlmostEqual(parts["Parapet"]["top_y"], 4.93, places=2)

    def test_nothing_blocks_the_openings_or_the_ramp(self):
        from reality import facade_727
        parts, spec = self._parts()
        self.assertEqual(facade_727.covered(spec, list(parts.values())), [])
        ramp = spec["interior"]["entry_ramp"]
        (fu, fv), (tu, tv) = ramp["from_uv"], ramp["to_uv"]
        walk = shapely.LineString([(fu, fv), (tu, tv)]).buffer(0.75, cap_style="flat")
        for p in parts.values():
            if p.get("collision"):
                (u0, y0, v0), (u1, y1, v1) = p["box"]
                if y1 > 0.3 and y0 < 2.91:  # anything between the ground and the door head
                    self.assertLess(shapely.box(u0, v0, u1, v1).intersection(walk).area, 1e-4, p["name"])

    def test_accent_bands_frame_the_narrow_windows(self):
        from reality import facade_727
        parts, spec = self._parts()
        narrow = [o for o in spec["interior"]["openings"] if o["name"].startswith("NarrowWindow")]
        self.assertEqual(len(narrow), 6)
        for o in narrow:
            n = o["name"].removeprefix("NarrowWindow")
            left, right = parts[f"AccentStrip{n}L"]["box"], parts[f"AccentStrip{n}R"]["box"]
            self.assertAlmostEqual((left[0][0] + right[1][0]) / 2, o["centre_uv"][0], places=3)
            self.assertAlmostEqual(right[1][0] - left[0][0], facade_727.STRIP_W, places=3)
            self.assertAlmostEqual(parts[f"AccentStrip{n}B"]["box"][1][1], o["y0"], places=3)
            self.assertAlmostEqual(parts[f"AccentStrip{n}T"]["box"][0][1], o["y1"], places=3)

    def test_covered_sees_a_box_in_front_of_a_window(self):
        from reality import facade_727
        _, spec = self._parts()
        o = next(o for o in spec["interior"]["openings"] if o["name"] == "FrontWindow2")
        (cu, cv), dv = o["centre_uv"], o["outward_uv"][1]
        crate = facade_727._box("Crate", "wood_tile", cu - 0.3, 0.0, cv + 0.2 * dv, cu + 0.3, 2.0, cv + 0.6 * dv, "test")
        self.assertEqual(facade_727.covered(spec, [crate]), [("Crate", "FrontWindow2")])

    def test_end_walls_carry_bands_and_a_closed_service_door(self):
        parts, spec = self._parts()
        g = spec["interior"]["layout"]["faces"]
        nw, se = parts["ServiceDoorNW"]["box"], parts["ServiceDoorSE"]["box"]
        self.assertAlmostEqual(nw[0][0], g["W"] - 0.04, places=2)  # leaf on the NW end face
        self.assertAlmostEqual((nw[0][2] + nw[1][2]) / 2 - g["B"], 4.41, delta=0.05)  # A2.01 NW: 3.90-4.91 m from the back
        self.assertAlmostEqual(g["F"] - (se[0][2] + se[1][2]) / 2, 6.58, delta=0.05)  # A2.01 SE: 6.08-7.08 m from the front
        self.assertAlmostEqual(nw[1][1], 7 * 0.3048, places=2)
        ends = [p for p in parts.values() if p["name"].startswith("EndBand")]
        self.assertEqual(len({p["name"][:10] for p in ends}), 8, "4 bands NW, 3 bands and the door panel SE")
        for name in ("ServiceCanopyNW", "ServiceCanopySE", "ElectricServiceSE", "ServiceDoorNWInside", "ServiceDoorSEInside"):
            self.assertIn(name, parts)
        inside = parts["ServiceDoorSEInside"]["box"]
        self.assertAlmostEqual(inside[0][1], spec["interior"]["floor_y"], places=3)
        self.assertAlmostEqual(inside[0][0], spec["interior"]["layout"]["lines"]["E"] - 0.04, places=2)

    def test_bands_are_cut_around_the_service_doors(self):
        parts, _ = self._parts()
        for door in ("ServiceDoorNW", "ServiceDoorSE"):
            (du0, dy0, dv0), (du1, dy1, dv1) = parts[door]["box"]
            for p in parts.values():
                if p["name"].startswith("EndBand"):
                    (u0, y0, v0), (u1, y1, v1) = p["box"]
                    overlap = min(v1, dv1) - max(v0, dv0) > 1e-3 and min(y1, dy1) - max(y0, dy0) > 1e-3 and abs(u0 - du0) < 0.2
                    self.assertFalse(overlap, (p["name"], door))

    def test_storefront_frame_and_a_stop_behind_the_fixed_leaf(self):
        parts, spec = self._parts()
        g = spec["interior"]["layout"]["faces"]
        head = parts["StorefrontHead"]["box"]
        self.assertAlmostEqual(head[1][2] - head[0][2], 8 * 0.3048, places=2)  # 8'-0" storefront, A2.01 NW
        self.assertAlmostEqual(head[1][1] - spec["interior"]["floor_y"], 8 * 0.3048, places=2)
        stop = parts["FixedLeafStop"]
        self.assertEqual(stop["collision"], "only")
        self.assertGreaterEqual(stop["box"][0][0], g["PW"] - 1e-6, "the stop stays inside the wall")

    def test_signpost_and_snow_come_from_the_spec_inputs(self):
        parts, spec = self._parts()
        sp = spec["surroundings"]["signpost"]
        base = parts["SignpostBase"]["box"]
        self.assertAlmostEqual((base[0][0] + base[1][0]) / 2, sp["uv"][0], places=3)
        self.assertAlmostEqual(base[0][1], sp["ground_y"], places=3)
        self.assertTrue(all(t["kind"] in ("plate", "text") for n, t in parts.items() if n.startswith("Sign") and n != "Sign"
                            and not n.startswith("Signpost")))
        d = spec["surroundings"]["snow"]["flat_depth_m"]
        roof = parts["SnowRoof"]
        self.assertAlmostEqual(roof["top_y"] - roof["bottom_y"], d, places=3)
        self.assertIn("SnowCanopyFront", parts)
        self.assertIn("SnowPlanterWest", parts)

    def test_side_canopies_and_back_wall_follow_the_elevations(self):
        parts, _ = self._parts()
        self.assertEqual(sum(n.startswith("CanopyRodW") for n in parts), 3)
        self.assertEqual(sum(n.startswith("CanopyRodE") for n in parts), 3)
        self.assertEqual(sum(n.startswith("DrainLeader") for n in parts), 3)
        self.assertIn("BackGutter", parts)
        self.assertEqual(sum(n.startswith("RoofUnit") for n in parts), 2)

    def test_wall_paint_is_sw_7691_in_linear_light(self):
        from reality import facade_727
        self.assertEqual(facade_727.linear((227, 201, 161)), [0.7682, 0.5841, 0.3564])

    def test_sign_text_is_the_built_one(self):
        parts, _ = self._parts()
        self.assertEqual(parts["Sign"]["text"], "KEY WEST HEALTH CENTER")


class DocumentedRoof(unittest.TestCase):
    """A roof from the elevation sheets goes through the same shell as a lidar-fitted one."""

    ROOF = {"form": "hip_flat_top", "eave_m": 6.0, "top_m": 9.0, "pitch": 5 / 12}

    def _shell(self, roof):
        from reality import meshing
        poly = shapely.box(418000.0, 2715000.0, 418020.0, 2715040.0)  # 20 x 40 m
        return meshing.building_shell(None, poly, 1.0, roof["top_m"], False, None, 1.0, documented_roof=roof)

    def test_walls_stop_at_the_documented_eave(self):
        tops = [t for ring in self._shell(self.ROOF)["ring_top_y"] for t in ring]
        self.assertAlmostEqual(min(tops), 7.0, places=2)
        self.assertAlmostEqual(max(tops), 7.0, places=2)

    def test_roof_rises_at_the_pitch_to_a_flat_top(self):
        import numpy as np
        v = np.asarray(self._shell(self.ROOF)["roof_v"]).reshape(-1, 3)
        self.assertAlmostEqual(v[:, 1].max(), 10.0, places=2)
        self.assertGreater(int((np.abs(v[:, 1] - 10.0) < 1e-6).sum()), 3, "the centre stays flat at the top")

    def test_roof_source_names_the_documents(self):
        self.assertEqual(self._shell(self.ROOF)["roof_source"], "documented_hip_flat_top")

    def test_flat_roof_sits_at_the_documented_top(self):
        import numpy as np
        shell = self._shell({"form": "flat", "eave_m": 5.6, "top_m": 5.6})
        v = np.asarray(shell["roof_v"]).reshape(-1, 3)
        self.assertAlmostEqual(float(v[:, 1].min()), 6.6, places=2)
        self.assertAlmostEqual(float(v[:, 1].max()), 6.6, places=2)
        self.assertEqual(shell["roof_source"], "documented_flat")

    def test_roof_never_passes_the_documented_top(self):
        import numpy as np
        steep = dict(self.ROOF, pitch=3.0)
        v = np.asarray(self._shell(steep)["roof_v"]).reshape(-1, 3)
        self.assertLessEqual(v[:, 1].max(), 10.0 + 1e-6)


class LibraryPatch(unittest.TestCase):
    """Documented buildings join a committed library without the raw cache."""

    def _mini_library(self, tmp):
        from reality import build
        from reality.model import Feature
        a_fort = [f for f in self._documented() if f.feature_id.endswith("_a_fort")][0].geom.centroid
        old = Feature("kw:building:osm:w1", "buildings", "building", shapely.box(a_fort.x - 3, a_fort.y - 3, a_fort.x + 3, a_fort.y + 3),
                      "overture_2026_09_23_1", "w1", "identity", "derived", 0.8)
        far = Feature("kw:building:osm:w2", "buildings", "building", shapely.box(418000, 2715000, 418010, 2715010),
                      "overture_2026_09_23_1", "w2", "identity", "derived", 0.8)
        build.chunk_and_local([old, far])
        path = Path(tmp) / "lib.gpkg"
        library.write_layer(path, "buildings", [old, far], append=False)
        library._write_tables(path, [old, far], [], {"features": [], "assets": []}, {"schema_version": "test"})
        return path

    def _documented(self):
        from reality import documented
        return [f for f in documented.features(ids.IdRegistry()) if ":legistar_22_3575_" in f.feature_id]

    def _counts(self, path):
        import sqlite3
        con = sqlite3.connect(path)
        out = {"index": con.execute("SELECT COUNT(*) FROM feature_index").fetchone()[0],
               "heights": con.execute("SELECT COUNT(*) FROM attribute WHERE feature_id LIKE 'kw:building:doc:%' AND name = 'height_m'").fetchone()[0],
               "geometry_links": con.execute("SELECT COUNT(*) FROM source_link WHERE feature_id LIKE 'kw:building:doc:%' AND role = 'geometry'").fetchone()[0],
               "source": con.execute("SELECT COUNT(*) FROM source WHERE source_id = 'city_kw_legistar_22_3575'").fetchone()[0]}
        con.close()
        _, cols = library.read_layer("buildings", path)
        out["layer"] = len(cols["feature_id"])
        return out

    def test_patch_inserts_five_masses(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._mini_library(tmp)
            report = library.append_features(path, self._documented())
            self.assertEqual(len(report["inserted"]), 5)
            self.assertEqual(self._counts(path), {"index": 7, "heights": 5, "geometry_links": 5, "source": 1, "layer": 7})

    def test_patch_is_idempotent(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._mini_library(tmp)
            library.append_features(path, self._documented())
            first = self._counts(path)
            report = library.append_features(path, self._documented())
            self.assertEqual(self._counts(path), first)
            self.assertEqual(len(report["replaced"]), 5)

    def test_supersession_closes_the_old_feature(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._mini_library(tmp)
            entry = {"feature_id": "kw:building:osm:w2", "valid_to": "2023-09-18", "reason": "test"}
            self.assertEqual(library.close_features(path, [entry]), ["kw:building:osm:w2"])
            self.assertEqual(library.close_features(path, [entry]), ["kw:building:osm:w2"])
            _, cols = library.read_layer("buildings", path)
            closed = dict(zip(cols["feature_id"], cols["valid_to"]))
            self.assertEqual(closed["kw:building:osm:w2"], "2023-09-18")
            self.assertIsNone(closed["kw:building:osm:w1"])

    def test_overlap_is_reported(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = self._mini_library(tmp)
            report = library.append_features(path, self._documented())
            self.assertEqual(report["overlaps"], {"kw:building:doc:legistar_22_3575_a_fort": ["kw:building:osm:w1"]})


if __name__ == "__main__":
    unittest.main()
