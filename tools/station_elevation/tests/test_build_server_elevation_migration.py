import json
import unittest

from tools.station_elevation.build_server_elevation_migration import (
    ROOT,
    SNAPSHOT_PATH,
    _canonical_code,
    render_migration,
)


class ServerElevationMigrationTests(unittest.TestCase):
    def setUp(self):
        self.snapshot = json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))

    def test_every_station_has_a_unique_canonical_code_and_elevation(self):
        stations = self.snapshot["stations"]
        codes = [_canonical_code(station) for station in stations]

        self.assertEqual(len(stations), 681)
        self.assertEqual(len(codes), len(set(codes)))
        self.assertTrue(
            all(station.get("elevation_meters") is not None for station in stations)
        )
        self.assertIn("25a", codes)
        self.assertIn("25b", codes)

    def test_generated_migration_keeps_user_values_and_uses_early_returns(self):
        migration_path = (
            ROOT
            / "supabase"
            / "migrations"
            / "20261017120000_server_climbing_elevation_backfill.sql"
        )
        committed_migration = migration_path.read_text(encoding="utf-8")
        migration = render_migration(self.snapshot)

        grid_version = (
            "ba5fc9033f5b93173e077885a8cc203b0638f65f582e6b8f545e59489596da69"
        )
        self.assertEqual(committed_migration.count(grid_version), 681)
        self.assertEqual(migration.count(grid_version), 681)
        self.assertIn("if new.net_elevation_meters is not null then", migration)
        self.assertIn("where trip.net_elevation_meters is null", migration)
        self.assertIn("perform public.refresh_profile_achievements", migration)
        self.assertIn("if found then", migration)
        self.assertNotIn("union all", migration)


if __name__ == "__main__":
    unittest.main()
