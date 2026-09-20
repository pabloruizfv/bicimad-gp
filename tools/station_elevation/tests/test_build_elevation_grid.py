import unittest
import gzip
import hashlib
import json

import numpy as np

from tools.station_elevation.build_elevation_grid import (
    ASSET_DIR,
    DEGREE_STEP,
    NODATA,
    NORTH,
    WEST,
    sample_elevation,
)


class ElevationGridTests(unittest.TestCase):
    def test_bundled_grid_checksum_matches_station_snapshot(self):
        metadata = json.loads(
            (ASSET_DIR / "station_terrain_10m.json").read_text(encoding="utf-8")
        )
        snapshot = json.loads(
            (ASSET_DIR / "station_catalog_snapshot.json").read_text(encoding="utf-8")
        )
        raw = gzip.decompress((ASSET_DIR / "station_terrain_10m.i16.gz").read_bytes())
        digest = hashlib.sha256(raw).hexdigest()
        self.assertEqual(metadata["grid_sha256"], digest)
        self.assertEqual(snapshot["elevation_grid_version"], digest)
        self.assertEqual(len(raw), metadata["width"] * metadata["height"] * 2)

    def test_sample_centers_and_bilinear_midpoint(self):
        grid = np.array([[1000, 2000], [3000, 4000]], dtype="<i2")
        self.assertEqual(
            sample_elevation(grid, NORTH - DEGREE_STEP / 2, WEST + DEGREE_STEP / 2),
            100.0,
        )
        self.assertEqual(
            sample_elevation(grid, NORTH - DEGREE_STEP, WEST + DEGREE_STEP),
            250.0,
        )

    def test_missing_cell_or_outside_coverage_is_unknown(self):
        grid = np.array([[1000, NODATA], [3000, 4000]], dtype="<i2")
        self.assertIsNone(
            sample_elevation(grid, NORTH - DEGREE_STEP, WEST + DEGREE_STEP)
        )
        self.assertIsNone(sample_elevation(grid, NORTH + 1, WEST))


if __name__ == "__main__":
    unittest.main()
