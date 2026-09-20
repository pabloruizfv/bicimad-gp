"""Build a compact, offline Madrid terrain grid from the public IGN MDT05 WCS.

Requires requests, numpy, rasterio and pyproj. Only the derived grid and
station elevations are written; downloaded GeoTIFF responses stay in memory.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import time

import numpy as np
import rasterio
from rasterio.io import MemoryFile
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
import requests


ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "assets" / "data"
SOURCE_URL = "https://servicios.idee.es/wcs-inspire/mdt"
SOURCE_COVERAGE = "Elevacion25830_5"
SOURCE_PAGE = (
    "https://centrodedescargas.cnig.es/CentroDescargas/"
    "modelo-digital-terreno-mdt05-primera-cobertura"
)
WEST, SOUTH, EAST, NORTH = -3.83, 40.32, -3.53, 40.53
DEGREE_STEP = 0.0001
UTM_WEST, UTM_SOUTH, UTM_EAST, UTM_NORTH = 428000, 4462000, 456000, 4488000
SOURCE_STEP_METERS = 10
TILE_METERS = 5000
NODATA = -32768


def sample_elevation(
    values: np.ndarray, latitude: float, longitude: float
) -> float | None:
    """Sample the final decimeter grid using the same center-based rule as Dart."""
    height, width = values.shape
    if not (WEST <= longitude <= EAST and SOUTH <= latitude <= NORTH):
        return None
    x = min(max((longitude - WEST) / DEGREE_STEP - 0.5, 0), width - 1)
    y = min(max((NORTH - latitude) / DEGREE_STEP - 0.5, 0), height - 1)
    x0, y0 = int(x), int(y)
    x1, y1 = min(x0 + 1, width - 1), min(y0 + 1, height - 1)
    dx, dy = x - x0, y - y0
    samples = (
        (values[y0, x0], (1 - dx) * (1 - dy)),
        (values[y0, x1], dx * (1 - dy)),
        (values[y1, x0], (1 - dx) * dy),
        (values[y1, x1], dx * dy),
    )
    if any(value == NODATA and weight > 1e-8 for value, weight in samples):
        return None
    return round(sum(int(value) * weight for value, weight in samples) / 10, 1)


def _fetch_tile(
    session: requests.Session, x0: int, y0: int, x1: int, y1: int
) -> np.ndarray:
    params = [
        ("SERVICE", "WCS"),
        ("VERSION", "2.0.1"),
        ("REQUEST", "GetCoverage"),
        ("COVERAGEID", SOURCE_COVERAGE),
        ("FORMAT", "image/tiff"),
        ("SUBSET", f"x({x0},{x1})"),
        ("SUBSET", f"y({y0},{y1})"),
        ("SCALEFACTOR", "0.5"),
    ]
    for attempt in range(3):
        try:
            response = session.get(SOURCE_URL, params=params, timeout=90)
            response.raise_for_status()
            if "tiff" not in response.headers.get("Content-Type", "").lower():
                raise ValueError("The IGN service did not return a GeoTIFF")
            with MemoryFile(response.content) as memory:
                with memory.open() as dataset:
                    expected_shape = (
                        (y1 - y0) // SOURCE_STEP_METERS,
                        (x1 - x0) // SOURCE_STEP_METERS,
                    )
                    if (
                        dataset.crs != rasterio.crs.CRS.from_epsg(25830)
                        or dataset.shape != expected_shape
                        or abs(dataset.bounds.left - x0) > 0.1
                        or abs(dataset.bounds.bottom - y0) > 0.1
                        or abs(dataset.bounds.right - x1) > 0.1
                        or abs(dataset.bounds.top - y1) > 0.1
                    ):
                        raise ValueError("Unexpected IGN tile geometry")
                    return dataset.read(1, masked=True).filled(NODATA).astype("<i2")
        except (requests.RequestException, rasterio.errors.RasterioError) as error:
            if attempt == 2:
                raise RuntimeError("IGN tile download failed after retries") from error
            time.sleep(2 * (attempt + 1))
    raise AssertionError("Unreachable")


def _build_grid(session: requests.Session) -> np.ndarray:
    source_width = (UTM_EAST - UTM_WEST) // SOURCE_STEP_METERS
    source_height = (UTM_NORTH - UTM_SOUTH) // SOURCE_STEP_METERS
    source = np.full((source_height, source_width), NODATA, dtype="<i2")
    xs = list(range(UTM_WEST, UTM_EAST, TILE_METERS))
    ys = list(range(UTM_SOUTH, UTM_NORTH, TILE_METERS))
    total = len(xs) * len(ys)
    completed = 0
    for y0 in ys:
        for x0 in xs:
            x1, y1 = min(x0 + TILE_METERS, UTM_EAST), min(
                y0 + TILE_METERS, UTM_NORTH
            )
            tile = _fetch_tile(session, x0, y0, x1, y1)
            col = (x0 - UTM_WEST) // SOURCE_STEP_METERS
            row = (UTM_NORTH - y1) // SOURCE_STEP_METERS
            source[row : row + tile.shape[0], col : col + tile.shape[1]] = tile
            completed += 1
            print(f"IGN tiles: {completed}/{total}", flush=True)
            time.sleep(0.1)

    width = round((EAST - WEST) / DEGREE_STEP)
    height = round((NORTH - SOUTH) / DEGREE_STEP)
    target = np.full((height, width), np.nan, dtype="float32")
    reproject(
        source=source,
        destination=target,
        src_transform=from_origin(
            UTM_WEST, UTM_NORTH, SOURCE_STEP_METERS, SOURCE_STEP_METERS
        ),
        src_crs="EPSG:25830",
        src_nodata=NODATA,
        dst_transform=from_origin(WEST, NORTH, DEGREE_STEP, DEGREE_STEP),
        dst_crs="EPSG:4326",
        dst_nodata=np.nan,
        resampling=Resampling.bilinear,
    )
    result = np.full((height, width), NODATA, dtype="<i2")
    valid = np.isfinite(target) & (target >= -1000) & (target <= 3000)
    result[valid] = np.rint(target[valid] * 10).astype("<i2")
    print(f"Coverage: {valid.sum()}/{valid.size} cells", flush=True)
    return result


def _verify_stations(grid: np.ndarray) -> list[dict]:
    snapshot_path = ASSET_DIR / "station_catalog_snapshot.json"
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    stations = snapshot["stations"]
    for station in stations:
        elevation = sample_elevation(
            grid, station["latitude"], station["longitude"]
        )
        if elevation is None or not 300 <= elevation <= 1200:
            raise ValueError("The terrain grid does not cover every station")
        station["elevation_meters"] = elevation

    import sqlite3

    with sqlite3.connect(ASSET_DIR / "legacy_route_models.sqlite") as connection:
        historical = connection.execute(
            "SELECT latitude, longitude FROM stations WHERE latitude IS NOT NULL "
            "AND longitude IS NOT NULL"
        ).fetchall()
    if any(sample_elevation(grid, lat, lon) is None for lat, lon in historical):
        raise ValueError("The terrain grid does not cover every historical station")
    print(f"Validated {len(stations)} current and {len(historical)} historical stations")
    return snapshot


def _write_atomic(path: Path, data: bytes) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--build", action="store_true", help="Download IGN MDT05 and regenerate assets"
    )
    mode.add_argument(
        "--reuse-grid", action="store_true", help="Revalidate the existing grid without network"
    )
    args = parser.parse_args()
    if args.build:
        with requests.Session() as session:
            grid = _build_grid(session)
    else:
        raw = gzip.decompress(
            (ASSET_DIR / "station_terrain_10m.i16.gz").read_bytes()
        )
        shape = (
            round((NORTH - SOUTH) / DEGREE_STEP),
            round((EAST - WEST) / DEGREE_STEP),
        )
        grid = np.frombuffer(raw, dtype="<i2").reshape(shape)
    grid_bytes = grid.tobytes()
    grid_version = hashlib.sha256(grid_bytes).hexdigest()
    snapshot = _verify_stations(grid)
    snapshot["elevation_grid_version"] = grid_version
    metadata = {
        "format_version": 1,
        "source": "IGN/CNIG PNOA MDT05 first coverage",
        "source_url": SOURCE_PAGE,
        "source_coverage": SOURCE_COVERAGE,
        "license": "CC BY 4.0; attribution: IGN/CNIG",
        "west": WEST,
        "south": SOUTH,
        "east": EAST,
        "north": NORTH,
        "step_degrees": DEGREE_STEP,
        "width": int(grid.shape[1]),
        "height": int(grid.shape[0]),
        "scale_meters": 0.1,
        "nodata": NODATA,
        "encoding": "gzip-int16-little-endian",
        "grid_sha256": grid_version,
    }
    _write_atomic(
        ASSET_DIR / "station_terrain_10m.json",
        (json.dumps(metadata, indent=2) + "\n").encode("utf-8"),
    )
    _write_atomic(
        ASSET_DIR / "station_terrain_10m.i16.gz",
        gzip.compress(grid_bytes, compresslevel=9, mtime=0),
    )
    _write_atomic(
        ASSET_DIR / "station_catalog_snapshot.json",
        (json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n").encode(
            "utf-8"
        ),
    )


if __name__ == "__main__":
    main()
