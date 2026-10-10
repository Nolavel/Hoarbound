"""Source acquisition into the git-ignored raw cache, with receipts.

Every acquirer is deterministic for a given source version: Overture releases and
USGS/NOAA objects are immutable or identified by ETag, recorded in the receipt.
"""
from __future__ import annotations

import concurrent.futures as cf
import os
import shutil
import tempfile
import time
import urllib.request
import warnings
import zipfile
from pathlib import Path

import numpy as np
import shapely

from . import config, frame, paths, receipts

OVERTURE_RELEASE = "2026-09-23.1"
OVERTURE_TYPES = [
    ("buildings", "building"), ("buildings", "building_part"),
    ("transportation", "segment"), ("transportation", "connector"),
    ("base", "infrastructure"), ("base", "land"), ("base", "water"),
    ("base", "land_use"), ("base", "land_cover"),
    ("places", "place"), ("addresses", "address"), ("divisions", "division_area"),
]
TNM = "https://prd-tnm.s3.amazonaws.com/StagedProducts/"
TNM_PRODUCTS = {
    "usgs_nsd_fl_20260227": ("Struct/GPKG/STRUCT_Florida_State_GPKG", ["Struct_Poly_FEMA", "Struct_Point"]),
    "usgs_ntd_fl_20260211": ("Tran/GPKG/TRAN_Florida_State_GPKG", ["Trans_RoadSegment", "Trans_AirportRunway", "Trans_AirportPoint", "Trans_TrailSegment"]),
    "usgs_govtunit_fl_20260212": ("GovtUnit/GPKG/GOVTUNIT_Florida_State_GPKG", ["GU_IncorporatedPlace", "GU_UnincorporatedPlace", "GU_Reserve", "GU_CountyOrEquivalent"]),
    "usgs_nhd_fl_2024": ("Hydrography/NHD/State/GPKG/NHD_H_Florida_State_GPKG", ["NHDWaterbody", "NHDArea", "NHDLine", "NHDFlowline"]),
}
NOAA = "https://noaa-nos-coastal-lidar-pds.s3.amazonaws.com/"
DEM_URL = NOAA + "dem/NGS_FL_key_west_DEM_2016_6366/2016_key_west_mosaic_m6366.tif"
LIDAR = {
    "noaa_lidar_9081": {"index": "laz/geoid18/9081/tileindex_2019_NGS_FL_topobathy_Irma_m9081.gpkg", "cell_m": 0.5, "query_res_m": 0.5},
    "noaa_lidar_6246": {"index": "laz/geoid18/6246/tileindex_fl2016_ngs_topobathy_key_west_m6246.gpkg", "cell_m": 1.0, "query_res_m": 1.0},
}
WORLDCOVER_URL = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N24W084_Map.tif"


def _log(*args) -> None:
    print("[acquire]", *args, flush=True)


def _download(url: str, out: Path) -> dict:
    head = receipts.http_head(url)
    if out.exists() and out.stat().st_size == head["bytes"]:
        _log("cached", out.name)
    else:
        out.parent.mkdir(parents=True, exist_ok=True)
        _log("download", url)
        tmp = out.with_suffix(out.suffix + ".part")
        with urllib.request.urlopen(url, timeout=600) as response, open(tmp, "wb") as handle:
            shutil.copyfileobj(response, handle, 1 << 22)
        tmp.replace(out)
    return {**head, "url": url, "sha256": receipts.sha256_file(out), "local_path": paths.rel(out)}


# --- Overture -------------------------------------------------------------

def overture(bbox: tuple[float, float, float, float] | None = None) -> None:
    import pyarrow.compute as pc
    import pyarrow.dataset as ds
    import pyarrow.fs as fs
    import pyarrow.parquet as pq

    west, south, east, north = bbox or config.acquisition_bbox()
    proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    kwargs = {"anonymous": True, "region": "us-west-2"}
    if proxy:
        kwargs["proxy_options"] = proxy
    s3 = fs.S3FileSystem(**kwargs)
    receipt = receipts.load("overture_2026_09_23_1")
    receipt.update({"release": OVERTURE_RELEASE, "retrieved_at": receipts.now_utc(),
                    "query_bbox_lonlat": [west, south, east, north],
                    "predicate": "bbox.xmin < east AND bbox.xmax > west AND bbox.ymin < north AND bbox.ymax > south"})
    out_dir = paths.RAW / "overture" / OVERTURE_RELEASE
    out_dir.mkdir(parents=True, exist_ok=True)
    for theme, typ in OVERTURE_TYPES:
        prefix = f"overturemaps-us-west-2/release/{OVERTURE_RELEASE}/theme={theme}/type={typ}"
        t0 = time.time()
        dataset = ds.dataset(prefix, filesystem=s3, format="parquet")
        flt = ((pc.field("bbox", "xmin") < east) & (pc.field("bbox", "xmax") > west)
               & (pc.field("bbox", "ymin") < north) & (pc.field("bbox", "ymax") > south))
        table = dataset.to_table(filter=flt)
        out = out_dir / f"{theme}__{typ}.parquet"
        pq.write_table(table, out, compression="zstd")
        _log(f"overture {theme}/{typ}: {table.num_rows} rows in {time.time() - t0:.1f}s")
        receipts.upsert_artifact(receipt, {
            "name": f"{theme}/{typ}", "remote": f"s3://{prefix}/", "rows": table.num_rows,
            "local_path": paths.rel(out), "sha256": receipts.sha256_file(out),
        })
    receipts.save(receipt)


# --- USGS The National Map --------------------------------------------------

def usgs_tnm(only: list[str] | None = None) -> None:
    import pyogrio

    west, south, east, north = config.acquisition_bbox()
    for source_id, (stem, layers) in TNM_PRODUCTS.items():
        if only and source_id not in only:
            continue
        receipt = receipts.load(source_id)
        receipt["retrieved_at"] = receipts.now_utc()
        receipt["query_bbox_lonlat"] = [west, south, east, north]
        zip_path = paths.RAW / "usgs_tnm" / f"{Path(stem).name}.zip"
        art = _download(TNM + stem + ".zip", zip_path)
        meta = _download(TNM + stem + ".xml", zip_path.with_suffix(".xml"))
        receipts.upsert_artifact(receipt, {"name": "archive", **art})
        receipts.upsert_artifact(receipt, {"name": "fgdc_metadata", **meta})
        clip = paths.RAW / "usgs_tnm" / "clips" / f"{source_id}.gpkg"
        clip.parent.mkdir(parents=True, exist_ok=True)
        if clip.exists():
            clip.unlink()
        with tempfile.TemporaryDirectory(dir=paths.RAW) as tmp:
            with zipfile.ZipFile(zip_path) as zf:
                member = next(n for n in zf.namelist() if n.endswith(".gpkg"))
                _log("extract", member)
                zf.extract(member, tmp)
            src = Path(tmp) / member
            counts = {}
            for layer in layers:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    meta_l, _, geom, fields = pyogrio.raw.read(src, layer=layer, bbox=(west, south, east, north))
                    pyogrio.raw.write(clip, geom, fields, meta_l["fields"], layer=layer, driver="GPKG",
                                      crs=meta_l["crs"], geometry_type=meta_l["geometry_type"], append=clip.exists())
                counts[layer] = len(geom)
                _log(source_id, layer, counts[layer])
        receipts.upsert_artifact(receipt, {"name": "clip", "local_path": paths.rel(clip), "layers": counts,
                                           "sha256": receipts.sha256_file(clip)})
        receipts.save(receipt)


# --- NOAA DEM -----------------------------------------------------------------

def noaa_dem() -> None:
    import rasterio
    from rasterio.windows import from_bounds

    ext = config.extent()["projected_bounds"]
    pad = 64.0
    out = paths.RAW / "noaa_dem_6366" / "dem_6366_extent_1m.tif"
    out.parent.mkdir(parents=True, exist_ok=True)
    head = receipts.http_head(DEM_URL)
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
                      GDAL_HTTP_MAX_RETRY="4", GDAL_HTTP_RETRY_DELAY="2"):
        with rasterio.open("/vsicurl/" + DEM_URL) as src:
            win = from_bounds(ext["min_e"] - pad, ext["min_n"] - pad, ext["max_e"] + pad, ext["max_n"] + pad, src.transform)
            win = win.round_offsets().round_lengths()
            _log("DEM window", win)
            data = src.read(1, window=win)
            profile = src.profile.copy()
            profile.update(driver="GTiff", width=data.shape[1], height=data.shape[0], transform=src.window_transform(win),
                           compress="deflate", predictor=3, tiled=True, blockxsize=512, blockysize=512, BIGTIFF="IF_SAFER")
            nodata = src.nodata
    with rasterio.open(out, "w", **profile) as dst:
        dst.write(data, 1)
    valid = data[data != nodata] if nodata is not None else data
    receipt = receipts.load("noaa_dem_6366")
    receipt.update({"retrieved_at": receipts.now_utc(), "remote": {"url": DEM_URL, **head},
                    "full_file_sha256_from_terrain_receipt": "573bd136a230263af78e3eeda5b554efe42d2cc38eea0cda3d2dbd8744c572cb",
                    "identity_check": "ETag equals world/terrain/source/key_west/noaa_source_receipt.json etag",
                    "window": "native 1 m pixels, no resampling", })
    receipts.upsert_artifact(receipt, {"name": "extent_crop_1m", "local_path": paths.rel(out), "sha256": receipts.sha256_file(out),
                                       "width": int(data.shape[1]), "height": int(data.shape[0]),
                                       "height_range_m": [float(valid.min()), float(valid.max())]})
    receipts.save(receipt)


# --- NOAA lidar (COPC) ------------------------------------------------------

def _rasterize_tile(url: str, bounds: tuple[float, float, float, float], cell: float, res: float, out: Path) -> dict:
    import laspy

    if out.exists():
        with np.load(out) as z:
            return {"url": url, "points": int(z["points"]), "cached": True}
    for attempt in range(4):
        try:
            with laspy.CopcReader.open(url) as reader:
                header = reader.header
                pts = reader.query(resolution=res)
            break
        except Exception as exc:  # network hiccup; retried with backoff
            if attempt == 3:
                raise
            time.sleep(2 ** (attempt + 1))
            _log("retry", url, exc)
    minx, miny, maxx, maxy = bounds
    ncol = int(round((maxx - minx) / cell))
    nrow = int(round((maxy - miny) / cell))
    x = np.asarray(pts.x)
    y = np.asarray(pts.y)
    z = np.asarray(pts.z, dtype=np.float32)
    cls = np.asarray(pts.classification)
    keep = (cls != 7) & (cls != 18) & (x >= minx) & (x < maxx) & (y > miny) & (y <= maxy)
    col = ((x - minx) / cell).astype(np.int64)
    row = ((maxy - y) / cell).astype(np.int64)
    keep &= (col >= 0) & (col < ncol) & (row >= 0) & (row < nrow)
    idx = row * ncol + col
    dsm = np.full(nrow * ncol, -np.inf, dtype=np.float32)
    np.maximum.at(dsm, idx[keep], z[keep])
    g = keep & (cls == 2)
    gsum = np.bincount(idx[g], weights=z[g], minlength=nrow * ncol)
    gcnt = np.bincount(idx[g], minlength=nrow * ncol)
    ground = np.where(gcnt > 0, gsum / np.maximum(gcnt, 1), np.nan).astype(np.float32)
    ncount = np.bincount(idx[keep & (cls != 2)], minlength=nrow * ncol).astype(np.uint16)
    dsm[~np.isfinite(dsm)] = np.nan
    out.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(out, dsm=dsm.reshape(nrow, ncol), ground=ground.reshape(nrow, ncol),
                        nonground_count=ncount.reshape(nrow, ncol), origin=np.array([minx, maxy]),
                        cell=np.array(cell), points=np.array(len(x)))
    return {"url": url, "points": int(len(x)), "header_points": int(header.point_count), "cached": False}


def noaa_lidar(only: list[str] | None = None, workers: int = 6) -> None:
    import pyogrio

    land = _library_land_mask()
    for source_id, spec in LIDAR.items():
        if only and source_id not in only:
            continue
        index = paths.RAW / source_id / Path(spec["index"]).name
        idx_art = _download(NOAA + spec["index"], index)
        meta, _, geom, fields = pyogrio.raw.read(index)
        names = list(meta["fields"])
        urls = fields[names.index("url")]
        tiles = shapely.from_wkb(geom)
        chosen = [(str(urls[i]), tiles[i].bounds) for i in range(len(tiles)) if tiles[i].intersects(land)]
        _log(source_id, "tiles over library land:", len(chosen))
        results = []
        with cf.ThreadPoolExecutor(workers) as ex:
            futs = {ex.submit(_rasterize_tile, u, b, spec["cell_m"], spec["query_res_m"],
                              paths.RAW / source_id / "grids" / (Path(u).name.replace(".copc.laz", ".npz"))): u for u, b in chosen}
            for n, fut in enumerate(cf.as_completed(futs), 1):
                results.append(fut.result())
                if n % 20 == 0:
                    _log(source_id, f"{n}/{len(chosen)} tiles")
        heads = {}
        with cf.ThreadPoolExecutor(16) as ex:
            for url, head in zip([r["url"] for r in results], ex.map(receipts.http_head, [r["url"] for r in results])):
                heads[url] = head
        receipt = receipts.load(source_id)
        receipt.update({"retrieved_at": receipts.now_utc(), "query_resolution_m": spec["query_res_m"], "grid_cell_m": spec["cell_m"],
                        "grid_products": "dsm = max Z of non-noise points; ground = mean Z of class-2 points; nonground_count",
                        "tile_selection": "tiles intersecting library land (non-context) buffered 60 m"})
        receipts.upsert_artifact(receipt, {"name": "tile_index", **idx_art})
        receipts.upsert_artifact(receipt, {"name": "tiles", "count": len(results),
                                           "points_read": int(sum(r["points"] for r in results)),
                                           "tiles": sorted([{"url": r["url"], "etag": heads[r["url"]]["etag"], "bytes": heads[r["url"]]["bytes"],
                                                             "points_read": r["points"]} for r in results], key=lambda t: t["url"])})
        receipts.save(receipt)


def _library_land_mask():
    """Union of in-scope land from the extent stage (projected), buffered for lidar tile selection."""
    import pyogrio

    path = paths.RAW / "extent" / "extent_zones.gpkg"
    meta, _, geom, fields = pyogrio.raw.read(path, layer="land_in_scope")
    return shapely.union_all(shapely.from_wkb(geom)).buffer(60.0)


# --- ESA WorldCover -----------------------------------------------------------

def worldcover() -> None:
    import rasterio
    from rasterio.windows import from_bounds

    b = config.extent()["lonlat_bounds"]
    out = paths.RAW / "esa_worldcover_2021_v200" / "worldcover_extent.tif"
    out.parent.mkdir(parents=True, exist_ok=True)
    head = receipts.http_head(WORLDCOVER_URL)
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"):
        with rasterio.open("/vsicurl/" + WORLDCOVER_URL) as src:
            win = from_bounds(b["west"] - 0.002, b["south"] - 0.002, b["east"] + 0.002, b["north"] + 0.002, src.transform)
            win = win.round_offsets().round_lengths()
            data = src.read(1, window=win)
            profile = src.profile.copy()
            profile.update(width=data.shape[1], height=data.shape[0], transform=src.window_transform(win), compress="deflate", tiled=False)
            profile.pop("blockxsize", None)
            profile.pop("blockysize", None)
    with rasterio.open(out, "w", **profile) as dst:
        dst.write(data, 1)
    receipt = receipts.load("esa_worldcover_2021_v200")
    receipt.update({"retrieved_at": receipts.now_utc(), "remote": {"url": WORLDCOVER_URL, **head}})
    receipts.upsert_artifact(receipt, {"name": "extent_window", "local_path": paths.rel(out), "sha256": receipts.sha256_file(out),
                                       "classes_present": sorted(int(v) for v in np.unique(data))})
    receipts.save(receipt)


# --- Legacy committed snapshot ----------------------------------------------

def legacy() -> None:
    receipt = receipts.load("hoarbound_legacy_osm_2026_09_29")
    receipt["retrieved_at"] = receipts.now_utc()
    receipt["upstream_receipt"] = "data/world/key_west/source_receipt.json"
    for name in ("city_preview.json", "visual_enrichment.json"):
        p = paths.LEGACY / name
        receipts.upsert_artifact(receipt, {"name": name, "local_path": paths.rel(p), "sha256": receipts.sha256_file(p)})
    receipts.save(receipt)
