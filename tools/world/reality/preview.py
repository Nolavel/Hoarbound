"""Spatial-fidelity previews of the Reality Library (not art): docs/world/reality_previews/*.png.

Projected UTM coordinates are drawn north-up on a DEM hillshade, so offsets between
layers (vector vs lidar vs DEM) are visible at a glance.
"""
from __future__ import annotations

import json
import sqlite3

import numpy as np
import pyogrio
import shapely
from PIL import Image, ImageDraw, ImageFont

from . import config, frame, library, lidar, paths

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
INK = (34, 34, 38)
RECON_COLOURS = {"cross_verified": (24, 150, 90), "measured": (40, 110, 210), "authoritative": (120, 60, 200),
                 "derived": (230, 150, 30), "inferred": (215, 60, 60), "unknown": (150, 150, 150)}


class Canvas:
    def __init__(self, bounds, width: int, title: str, dem: lidar.DemCrop | None = None):
        self.minx, self.miny, self.maxx, self.maxy = bounds
        self.scale = width / (self.maxx - self.minx)
        self.w = width
        self.h = int(round((self.maxy - self.miny) * self.scale))
        self.img = Image.new("RGB", (self.w, self.h + 70), (246, 246, 244))
        if dem is not None:
            self._hillshade(dem)
        self.draw = ImageDraw.Draw(self.img, "RGBA")
        self.font = ImageFont.truetype(FONT, 15)
        self.small = ImageFont.truetype(FONT, 12)
        self.bold = ImageFont.truetype(FONT_B, 18)
        self.title = title
        self.legend: list[tuple[str, tuple]] = []

    def _hillshade(self, dem: lidar.DemCrop) -> None:
        t = dem.transform
        xs = self.minx + (np.arange(self.w) + 0.5) / self.scale
        ys = self.maxy - (np.arange(self.h) + 0.5) / self.scale
        cols = np.clip(((xs - t.c) / t.a).astype(int), 0, dem.data.shape[1] - 1)
        rows = np.clip(((ys - t.f) / t.e).astype(int), 0, dem.data.shape[0] - 1)
        z = dem.data[np.ix_(rows, cols)]
        z = np.nan_to_num(z, nan=-3.0)
        gy, gx = np.gradient(z, 1.0 / self.scale)
        shade = np.clip(0.75 + 0.35 * (-gx - gy) / np.sqrt(1 + gx * gx + gy * gy), 0.3, 1.0)
        land = z >= 0.0
        base = np.where(land[..., None], np.array([238, 230, 206]), np.array([165, 198, 226]))
        depth = np.clip(-z / 6.0, 0, 1)[..., None]
        base = np.where(land[..., None], base, base * (1 - 0.45 * depth))
        shade = np.where(land, shade, 0.85 + 0.15 * shade)
        rgb = (base * shade[..., None]).clip(0, 255).astype(np.uint8)
        self.img.paste(Image.fromarray(rgb), (0, 0))

    def px(self, coords) -> list[tuple[float, float]]:
        a = np.asarray(coords)
        return list(zip((a[:, 0] - self.minx) * self.scale, (self.maxy - a[:, 1]) * self.scale))

    def geom(self, g, fill=None, outline=None, width=1, radius=2.0) -> None:
        if g is None or g.is_empty:
            return
        t = g.geom_type
        if t.startswith("Multi") or t == "GeometryCollection":
            for part in g.geoms:
                self.geom(part, fill, outline, width, radius)
        elif t == "Polygon":
            if len(g.exterior.coords) >= 3:
                self.draw.polygon(self.px(g.exterior.coords), fill=fill, outline=outline, width=width)
        elif t in ("LineString", "LinearRing"):
            if len(g.coords) >= 2:
                self.draw.line(self.px(g.coords), fill=outline or fill, width=width)
        elif t == "Point":
            (x, y), = self.px([(g.x, g.y)])
            r = max(radius, 0.5)
            self.draw.ellipse([x - r, y - r, x + r, y + r], fill=fill, outline=outline)

    def key(self, label: str, colour) -> None:
        self.legend.append((label, colour))

    def save(self, name: str, note: str = "") -> None:
        d = self.draw
        d.rectangle([0, self.h, self.w, self.h + 70], fill=(255, 255, 255))
        d.text((10, self.h + 6), self.title, fill=INK, font=self.bold)
        x = 10
        for label, colour in self.legend:
            d.rectangle([x, self.h + 36, x + 14, self.h + 50], fill=colour)
            d.text((x + 19, self.h + 35), label, fill=INK, font=self.small)
            x += 26 + int(d.textlength(label, font=self.small))
        bar_m = _nice(self.w / self.scale / 6)
        bx = self.w - 20 - bar_m * self.scale
        d.rectangle([bx, self.h + 12, self.w - 20, self.h + 18], fill=INK)
        d.text((bx, self.h + 22), f"{bar_m:.0f} m", fill=INK, font=self.small)
        att = "Data: © OpenStreetMap contributors (ODbL) via Overture Maps; NOAA NGS/OCM lidar & DEM; USGS TNM; FEMA/ORNL USA Structures; ESA WorldCover 2021 (CC BY 4.0). North up, EPSG:32617."
        d.text((10, self.h + 54), att + (" " + note if note else ""), fill=(90, 90, 96), font=self.small)
        paths.PREVIEWS.mkdir(parents=True, exist_ok=True)
        small = self.img.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
        small.save(paths.PREVIEWS / name, optimize=True)
        print("[preview]", name, f"{self.w}x{self.h}")


def _nice(v: float) -> float:
    for s in (10, 20, 50, 100, 200, 250, 500, 1000, 2000, 5000):
        if s >= v * 0.6:
            return s
    return 5000


def _layers() -> dict:
    out = {}
    for fam in library.families():
        out[fam] = library.read_layer(fam)
    return out


def _selected_recon(name: str, family: str) -> dict:
    con = sqlite3.connect(paths.LIBRARY)
    rows = con.execute("""SELECT fi.feature_id, p.reconstruction_class FROM attribute_store a JOIN feature_index fi ON fi.fid = a.fid
                       JOIN attribute_name n ON n.name_id = a.name_id JOIN provenance p ON p.prov_id = a.prov_id
                       WHERE fi.family = ? AND n.name = ? AND a.selected = 1""", (family, name)).fetchall()
    con.close()
    return dict(rows)


def _box_local(x0, z0, x1, z1):
    e0, n0 = frame.local_to_projected(x0, z1)
    e1, n1 = frame.local_to_projected(x1, z0)
    return (e0, n0, e1, n1)


def run() -> None:
    L = _layers()
    dem = lidar.DemCrop()
    ext = config.extent()["projected_bounds"]
    full = (ext["min_e"], ext["min_n"], ext["max_e"], ext["max_n"])
    leg = frame.frame()["legacy_runtime_crop"]["projected"]
    zg, zc = library.read_layer("extent_zones")
    zones = {str(n): g for n, g in zip(zc["zone"], zg)}
    has_override = "game_override" in [n for n, _ in pyogrio.list_layers(paths.LIBRARY)]
    ov_g, ov_c = library.read_layer("game_override") if has_override else ([], {})

    def coast(c, colour=(20, 70, 120), w=1):
        g, col = L["coastline"]
        for geom, sub, scope in zip(g, col["subclass"], col["scope"]):
            if sub == "osm_coastline":
                c.geom(geom, outline=colour if scope == "reality" else (120, 120, 140), width=w)

    # 1. full extent
    c = Canvas(full, 2000, "Library extent — derived from data (core islands, adjacent islets, crossing, 1 km water margin)", dem)
    c.geom(zones["in_scope_land"], fill=(70, 150, 90, 90))
    c.geom(zones["boca_chica_silhouette"], fill=(150, 110, 170, 110))
    c.geom(zones.get("context_land", shapely.Polygon()), fill=(150, 110, 170, 110))
    c.geom(shapely.box(leg["min_e"], leg["min_n"], leg["max_e"], leg["max_n"]).exterior, outline=(200, 60, 40), width=3)
    c.geom(zones["library_extent"].exterior, outline=(20, 20, 20), width=4)
    c.geom(zones["crossing"], fill=(240, 160, 0), outline=(240, 160, 0), width=4)
    coast(c)
    _chunk_grid(c)
    c.key("in-scope land", (70, 150, 90)); c.key("Boca Chica outline / context islets", (150, 110, 170)); c.key("legacy runtime crop", (200, 60, 40))
    c.key("library extent", (20, 20, 20)); c.key("Boca Chica Channel Bridge", (240, 160, 0)); c.key("512 m chunk grid", (180, 180, 180))
    c.save("01_full_extent.png")

    # 2. NE boundary
    ne = (424300, 2716900, 429250, 2722150)
    c = Canvas(ne, 1600, "North-east: added coverage vs legacy crop, Stock Island north shore, bridge approach, Boca Chica outline only", dem)
    c.geom(zones["added_vs_legacy"], fill=(255, 220, 80, 60))
    c.geom(zones["boca_chica_silhouette"], fill=(150, 110, 170, 110))
    c.geom(zones.get("context_land", shapely.Polygon()), fill=(150, 110, 170, 110))
    c.geom(zones["in_scope_land"], fill=(70, 150, 90, 70))
    _buildings(c, L, "plain")
    _roads(c, L, simple=True)
    coast(c, w=2)
    c.geom(shapely.box(leg["min_e"], leg["min_n"], leg["max_e"], leg["max_n"]).exterior, outline=(200, 60, 40), width=3)
    c.geom(zones["library_extent"].exterior, outline=(20, 20, 20), width=4)
    for g, t in zip(ov_g, ov_c.get("override_type", [])):
        c.geom(g, fill=(230, 30, 30, 200), outline=(230, 30, 30), width=6, radius=7)
    c.key("added vs legacy crop", (255, 220, 80)); c.key("Boca Chica (outline only)", (150, 110, 170)); c.key("in-scope land", (70, 150, 90))
    c.key("legacy crop edge", (200, 60, 40)); c.key("library edge", (20, 20, 20)); c.key("game override: severed span", (230, 30, 30))
    c.save("02_northeast_boundary.png")

    # 3. Key West island overview
    kw = _box_local(-5200, -2300, 2400, 2400)
    c = Canvas(kw, 2000, "Key West — combined reality layer (buildings by height provenance, roads, coast, vegetation)", dem)
    _vegetation(c, L, points=False)
    _roads(c, L, simple=True)
    _buildings(c, L, "height")
    coast(c)
    _height_keys(c)
    c.save("03_key_west_combined.png")

    # 4. Old Town buildings
    ot = _box_local(-3500, 450, -2000, 1450)
    c = Canvas(ot, 1800, "Old Town (Duval St / Bahama Village) — real footprints coloured by selected height provenance (no box proxies)", dem)
    _roads(c, L, simple=True)
    _buildings(c, L, "height", outline=True)
    _height_keys(c)
    c.save("04_buildings_old_town.png")

    # 5. Roads
    c = Canvas(kw, 2000, "Roads — OSM centrelines; green = cross-verified with Census TIGER, orange = OSM only, red = TIGER only", dem)
    _roads(c, L, simple=False)
    coast(c)
    c.key("cross-verified", (24, 150, 90)); c.key("OSM only", (230, 150, 30)); c.key("TIGER only (unverified)", (215, 60, 60)); c.key("footway/path", (120, 120, 120))
    c.save("05_roads.png")

    # 6. Coastal
    hb = _box_local(-3600, -1600, -400, 1000)
    c = Canvas(hb, 1800, "Coastal structures — piers, breakwaters, bridges; OSM coastline (blue) vs DEM 0 m NAVD88 shoreline (black)", dem)
    g, col = L["land"]
    for geom, cls in zip(g, col["class"]):
        if cls == "dem_land_above_navd88_0m":
            c.geom(geom.exterior if geom.geom_type == "Polygon" else geom.boundary, outline=(10, 10, 10), width=1)
    coast(c, colour=(30, 110, 230), w=2)
    cs, cc = L["coastal_structures"]
    for geom, cls, sub in zip(cs, cc["class"], cc["subclass"]):
        colour = {"pier": (170, 90, 30), "breakwater": (90, 90, 90), "groyne": (60, 60, 60)}.get(cls, (200, 120, 0))
        if sub == "floating":
            colour = (230, 60, 170)
        c.geom(geom, fill=colour + (200,), outline=colour, width=3, radius=3)
    for geom in L["bridges"][0]:
        c.geom(geom, fill=(240, 160, 0, 160), outline=(240, 160, 0), width=3)
    c.key("pier", (170, 90, 30)); c.key("floating pier", (230, 60, 170)); c.key("breakwater/groyne", (90, 90, 90)); c.key("bridge", (240, 160, 0))
    c.key("OSM coastline", (30, 110, 230)); c.key("DEM 0 m shoreline (2016)", (10, 10, 10))
    c.save("06_coastal_structures.png")

    # 7. Utilities
    c = Canvas(kw, 2000, "Utilities — power poles in line topology (green) vs position-only (red), lines, street lamps, hydrants, masts", dem)
    tg, tc = library.read_layer("utility_topology")
    for geom, a, b in zip(tg, tc["from_feature_id"], tc["to_feature_id"]):
        c.geom(geom, outline=(40, 40, 160) if a and b else (160, 120, 200), width=2)
    pg, pc = L["power"]
    for geom, cls, attrs in zip(pg, pc["class"], pc["attrs_json"]):
        if geom.geom_type == "Point":
            ok = json.loads(attrs).get("in_line_topology")
            c.geom(geom, fill=(24, 150, 90) if ok else (215, 60, 60), radius=3)
        else:
            c.geom(geom, fill=(120, 60, 200, 80), outline=(120, 60, 200), width=2)
    sg, sc = L["street_furniture"]
    for geom, cls in zip(sg, sc["class"]):
        colour = {"street_lamp": (250, 200, 0), "fire_hydrant": (255, 0, 0), "traffic_signals": (0, 200, 200)}.get(cls)
        if colour:
            c.geom(geom, fill=colour, radius=2.5)
    ug, uc = L["utilities"]
    for geom in ug:
        c.geom(geom, fill=(0, 0, 0), radius=3)
    coast(c)
    c.key("pole in topology", (24, 150, 90)); c.key("pole position-only", (215, 60, 60)); c.key("pole-to-pole edge", (40, 40, 160)); c.key("open-end edge", (160, 120, 200))
    c.key("street lamp", (250, 200, 0)); c.key("hydrant", (255, 0, 0)); c.key("signals", (0, 200, 200)); c.key("mast/tower/tank", (0, 0, 0))
    c.save("07_utility_infrastructure.png")

    # 8. Vegetation
    c = Canvas(kw, 2000, "Vegetation — OSM trees, lidar crown candidates (derived), dense lidar canopy, WorldCover mangrove, OSM wood/scrub/wetland", dem)
    _vegetation(c, L, points=True)
    coast(c)
    c.key("OSM tree", (0, 90, 0)); c.key("lidar crown candidate", (60, 170, 60)); c.key("dense canopy (lidar)", (30, 120, 60))
    c.key("mangrove (WorldCover)", (0, 140, 120)); c.key("wood/scrub/wetland (OSM)", (150, 190, 90))
    c.save("08_vegetation.png")

    # 9. bridge override
    br = (426700, 2718050, 428150, 2718700)
    c = Canvas(br, 1600, "Boca Chica Channel Bridge — reality (grey/orange) vs Hoarbound game override (red: removed deck, X: severed ends)", dem)
    _roads(c, L, simple=True)
    for geom in L["bridges"][0]:
        c.geom(geom, fill=(240, 160, 0, 120), outline=(240, 160, 0), width=2)
    for g, t in zip(ov_g, ov_c.get("override_type", [])):
        if t == "remove_span":
            c.geom(g, outline=(230, 30, 30), width=9)
        elif t == "severed_end":
            (x, y), = c.px([(g.x, g.y)])
            c.draw.line([x - 10, y - 10, x + 10, y + 10], fill=(230, 30, 30), width=4)
            c.draw.line([x - 10, y + 10, x + 10, y - 10], fill=(230, 30, 30), width=4)
    coast(c, w=2)
    c.key("reality: bridge outline", (240, 160, 0)); c.key("override: removed span", (230, 30, 30))
    c.save("09_bridge_override.png")


def _chunk_grid(c: Canvas) -> None:
    size = frame.chunk_size()
    oe, on = frame.origin()
    x = oe + np.floor((c.minx - oe) / size) * size
    while x <= c.maxx:
        c.geom(shapely.LineString([(x, c.miny), (x, c.maxy)]), outline=(150, 150, 150, 90))
        x += size
    y = on - np.floor((on - c.maxy) / size) * size
    while y >= c.miny:
        c.geom(shapely.LineString([(c.minx, y), (c.maxx, y)]), outline=(150, 150, 150, 90))
        y -= size


def _buildings(c: Canvas, L, mode: str, outline: bool = False) -> None:
    g, col = L["buildings"]
    recon = _selected_recon("height_m", "buildings") if mode == "height" else {}
    for geom, fid in zip(g, col["feature_id"]):
        if not geom.intersects(shapely.box(c.minx, c.miny, c.maxx, c.maxy)):
            continue
        colour = RECON_COLOURS.get(recon.get(fid, "unknown"), (150, 150, 150)) if mode == "height" else (110, 100, 95)
        c.geom(geom, fill=colour + (230,), outline=(30, 30, 30) if outline else None)


def _height_keys(c: Canvas) -> None:
    for k in ("cross_verified", "measured", "derived", "inferred", "unknown"):
        c.key({"cross_verified": "height lidar 2016+2019 agree", "measured": "height lidar 2019", "derived": "height tag/ML",
               "inferred": "height from levels", "unknown": "height unknown"}[k], RECON_COLOURS[k])


def _roads(c: Canvas, L, simple: bool) -> None:
    g, col = L["roads"]
    view = shapely.box(c.minx, c.miny, c.maxx, c.maxy)
    widths = {"trunk": 4, "primary": 4, "secondary": 3, "tertiary": 3, "residential": 2, "service": 1}
    for geom, cls, recon, flags in zip(g, col["class"], col["reconstruction_class"], col["flags"]):
        if not geom.intersects(view):
            continue
        w = widths.get(cls, 1)
        if simple:
            colour = (90, 90, 90) if cls not in ("footway", "path", "cycleway", "steps") else (160, 160, 160)
        elif flags and "single_source_unverified" in flags:
            colour = (215, 60, 60)
        elif cls in ("footway", "path", "cycleway", "steps", "pedestrian"):
            colour = (120, 120, 120)
        else:
            colour = (24, 150, 90) if recon == "cross_verified" else (230, 150, 30)
        c.geom(geom, outline=colour, width=w)


def _vegetation(c: Canvas, L, points: bool) -> None:
    vg, vc = L["vegetation_areas"]
    colours = {"lidar_canopy_dense": (30, 120, 60, 150), "mangrove": (0, 140, 120, 120), "wood": (150, 190, 90, 130),
               "scrub": (170, 200, 110, 120), "wetland": (120, 180, 170, 110), "wc_tree_cover": (90, 160, 90, 60),
               "wc_shrubland": (180, 200, 120, 50), "wc_herbaceous_wetland": (140, 200, 190, 60)}
    for geom, cls in zip(vg, vc["class"]):
        if cls in colours:
            c.geom(geom, fill=colours[cls])
    if points:
        tg, tc = L["trees"]
        for geom, sub, attrs in zip(tg, tc["subclass"], tc["attrs_json"]):
            if geom.geom_type != "Point":
                c.geom(geom, outline=(0, 90, 0), width=2)
                continue
            if sub == "lidar_candidate":
                c.geom(geom, fill=(60, 170, 60, 170), radius=max(0.8, json.loads(attrs).get("crown_radius_m", 2) * c.scale))
            else:
                c.geom(geom, fill=(0, 90, 0), radius=3)
