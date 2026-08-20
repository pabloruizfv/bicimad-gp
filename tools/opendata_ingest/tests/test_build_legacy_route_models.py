import math
import sqlite3
import tempfile
import unittest
import zipfile
import json
from pathlib import Path

from tools.opendata_ingest.build_legacy_route_models import (
    DataSource,
    StationReferenceResolver,
    _iter_station_payloads,
    _parse_malformed_202110_row,
    build_models,
    build_station_reference_resolver,
    discover_sources,
    extract_station_code,
    find_csv_sources,
    parse_timestamp,
    percentile,
    resolve_station_code,
    select_trip_sources,
    write_sqlite,
)


class LegacyRouteModelIngestTests(unittest.TestCase):
    def test_extracts_public_station_code(self):
        self.assertEqual(
            extract_station_code("34 - Jacinto Benavente"),
            ("34", "Jacinto Benavente"),
        )
        self.assertEqual(
            extract_station_code(" 164 - Paseo de las Delicias "),
            ("164", "Paseo de las Delicias"),
        )
        self.assertEqual(
            extract_station_code("001 b - Puerta del Sol B"),
            ("1b", "Puerta del Sol B"),
        )
        self.assertIsNone(extract_station_code("Jacinto Benavente"))

    def test_resolves_station_code_from_name_before_station_id(self):
        self.assertEqual(
            resolve_station_code("164 - Paseo de las Delicias", "999"),
            ("164", "Paseo de las Delicias"),
        )
        self.assertEqual(
            resolve_station_code("Plaza de Lavapiés", "57"),
            ("57", "Plaza de Lavapiés"),
        )
        self.assertIsNone(resolve_station_code("Plaza de Lavapiés", "station-api-id"))

    def test_resolves_legacy_station_id_to_public_code_from_reference(self):
        resolver = StationReferenceResolver()
        resolver.remember(
            original_id="8",
            public_code="7",
            name="Hortaleza",
        )

        self.assertEqual(
            resolve_station_code("Hortaleza", "8", resolver),
            ("7", "Hortaleza"),
        )

    def test_reads_csv_filters_invalid_rows_and_separates_directions(self):
        routes, stations, counters = build_models(_fixtures_dir())

        self.assertEqual(counters.files_total, 1)
        self.assertEqual(counters.valid_trips, 3)
        self.assertGreaterEqual(counters.rejected_trips, 5)
        self.assertIn(("34", "164"), routes)
        self.assertIn(("164", "34"), routes)
        self.assertEqual(routes[("34", "164")].count, 2)
        self.assertEqual(routes[("164", "34")].count, 1)
        self.assertIn("34", stations)
        self.assertEqual(stations["34"]["name"], "Jacinto Benavente")

    def test_calculates_duration_from_timestamps_and_histogram(self):
        routes, _, _ = build_models(_fixtures_dir())
        stats = routes[("34", "164")]
        (
            upper_cutoff_seconds,
            displayed_count,
            outlier_count,
            bin_edges,
            bin_counts,
        ) = stats.histogram()

        self.assertEqual(stats.count, 2)
        self.assertEqual(stats.best_seconds, 600)
        self.assertEqual(upper_cutoff_seconds, 718.8)
        self.assertEqual(displayed_count, 1)
        self.assertEqual(outlier_count, 1)
        self.assertEqual(len(bin_edges), 33)
        self.assertEqual(len(bin_counts), 32)
        self.assertEqual(sum(bin_counts), 1)

    def test_percentile_uses_linear_interpolation(self):
        self.assertEqual(percentile([100, 200, 300, 400], 0), 100)
        self.assertEqual(percentile([100, 200, 300, 400], 1), 400)
        self.assertEqual(percentile([100, 200, 300, 400], 0.5), 250)

    def test_parses_legacy_timezone_without_colon(self):
        parsed = parse_timestamp("2017-04-01T01:00:00.000+0200")

        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.utcoffset().total_seconds(), 7200)

    def test_iqr_cutoff_excludes_extreme_values_from_histogram_only(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = Path(temp_dir)
            (input_dir / "sample_outlier.csv").write_text(
                "\n".join(
                    [
                        "fecha;idBike;fleet;trip_minutes;geolocation_unlock;address_unlock;unlock_date;locktype;unlocktype;geolocation_lock;address_lock;lock_date;station_unlock;dock_unlock;unlock_station_name;station_lock;dock_lock;lock_station_name",
                        "2023-01-01;1;1;1.67;{};;2023-01-01T10:00:00;STATION;STATION;{};;2023-01-01T10:01:40;1;1;1 - Origen;2;1;2 - Destino",
                        "2023-01-01;2;1;1.83;{};;2023-01-01T11:00:00;STATION;STATION;{};;2023-01-01T11:01:50;1;1;1 - Origen;2;1;2 - Destino",
                        "2023-01-01;3;1;2.00;{};;2023-01-01T12:00:00;STATION;STATION;{};;2023-01-01T12:02:00;1;1;1 - Origen;2;1;2 - Destino",
                        "2023-01-01;4;1;2.17;{};;2023-01-01T13:00:00;STATION;STATION;{};;2023-01-01T13:02:10;1;1;1 - Origen;2;1;2 - Destino",
                        "2023-01-01;5;1;2.33;{};;2023-01-01T14:00:00;STATION;STATION;{};;2023-01-01T14:02:20;1;1;1 - Origen;2;1;2 - Destino",
                        "2023-01-01;6;1;16.67;{};;2023-01-01T15:00:00;STATION;STATION;{};;2023-01-01T15:16:40;1;1;1 - Origen;2;1;2 - Destino",
                    ]
                ),
                encoding="utf-8",
            )
            routes, _, _ = build_models(input_dir)
        stats = routes[("1", "2")]
        (
            upper_cutoff_seconds,
            displayed_count,
            outlier_count,
            _,
            bin_counts,
        ) = stats.histogram()

        self.assertEqual(stats.count, 6)
        self.assertEqual(stats.best_seconds, 100)
        self.assertLess(upper_cutoff_seconds, 1000)
        self.assertEqual(displayed_count, 5)
        self.assertEqual(outlier_count, 1)
        self.assertEqual(sum(bin_counts), 5)

    def test_writes_sqlite_without_individual_trips(self):
        routes, stations, counters = build_models(_fixtures_dir())
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "legacy.sqlite"
            write_sqlite(output, routes, stations, counters)

            connection = sqlite3.connect(output)
            try:
                route_count = connection.execute(
                    "SELECT COUNT(*) FROM route_models"
                ).fetchone()[0]
                tables = {
                    row[0]
                    for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type = 'table'"
                    )
                }
                row = connection.execute(
                    """
                    SELECT
                      total_count, displayed_count, outlier_count,
                      upper_cutoff_seconds, best_seconds,
                      bin_edges, bin_counts,
                      model_family, model_version
                    FROM route_models
                    WHERE origin_station_code = '34'
                      AND destination_station_code = '164'
                    """
                ).fetchone()
            finally:
                connection.close()

            self.assertEqual(route_count, 2)
            self.assertNotIn("trips", tables)
            self.assertEqual(row[0], 2)
            self.assertEqual(row[1], 1)
            self.assertEqual(row[2], 1)
            self.assertEqual(row[4], 600)
            self.assertEqual(len(json.loads(row[5])), 33)
            self.assertEqual(len(json.loads(row[6])), 32)
            self.assertEqual(row[7], "empirical_histogram")
            self.assertTrue(row[8])

    def test_reads_2022_csv_inside_zip_mapping_station_ids_to_public_codes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = Path(temp_dir)
            csv_zip = input_dir / "trips_22_01_January-csv.zip"
            json_zip = input_dir / "202201-json.zip"
            with zipfile.ZipFile(csv_zip, "w") as archive:
                archive.writestr(
                    "trips_22_01_January.csv",
                    "\n".join(
                        [
                            "fecha;idTrip;idBike;fleet;trip_minutes;geolocation_unlock;address_unlock;unlock_date;locktype;unlocktype;geolocation_lock;address_lock;lock_date;station_unlock;dock_unlock;unlock_station_name;station_lock;dock_lock;lock_station_name",
                            "2022-01-01;t1;1;1;16.28;{'type': 'Point', 'coordinates': [-3.6714166, 40.4318611]};;2022-01-01T00:02:20;STATION;STATION;{'type': 'Point', 'coordinates': [-3.688398, 40.419752]};;2022-01-01T00:18:37;200;3;Avenida de los Toreros;64;4;Plaza de la Independencia",
                            "2022-01-01;t2;1;1;10;{};;2022-01-01T01:00:00;STATION;STATION;{};;2022-01-01T01:10:00;57;1;53 - Plaza de Lavapiés;38;2;38 - Jacinto Benavente",
                        ]
                    ),
                )
            with zipfile.ZipFile(json_zip, "w") as archive:
                archive.writestr(
                    "202201.json",
                    json.dumps(
                        {
                            "stations": [
                                {
                                    "id": 200,
                                    "number": "192",
                                    "name": "Avenida de los Toreros",
                                },
                                {
                                    "id": 64,
                                    "number": "60",
                                    "name": "Plaza de la Independencia",
                                },
                            ],
                        }
                    )
                    + "\n",
                )

            sources = find_csv_sources(input_dir)
            resolver = build_station_reference_resolver(input_dir)
            routes, stations, counters = build_models(input_dir)

        self.assertEqual(len(sources), 1)
        self.assertEqual(
            resolve_station_code("Avenida de los Toreros", "200", resolver),
            ("192", "Avenida de los Toreros"),
        )
        self.assertEqual(counters.files_total, 1)
        self.assertEqual(counters.valid_trips, 2)
        self.assertIn(("192", "60"), routes)
        self.assertIn(("53", "38"), routes)
        self.assertIn("192", stations)
        self.assertEqual(stations["192"]["name"], "Avenida de los Toreros")

    def test_reads_legacy_json_and_maps_internal_station_ids(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = Path(temp_dir)
            with zipfile.ZipFile(input_dir / "Bicimad_Stations_201804.zip", "w") as archive:
                archive.writestr(
                    "Bicimad_Stations_201804.json",
                    json.dumps(
                        {
                            "stations": [
                                {"id": 8, "number": "7", "name": "Hortaleza"},
                                {"id": 9, "number": "8", "name": "Alonso Martinez"},
                            ]
                        }
                    )
                    + "\n",
                )
            with zipfile.ZipFile(input_dir / "201704_Usage_Bicimad.zip", "w") as archive:
                archive.writestr(
                    "201704_Usage_Bicimad.json",
                    "\n".join(
                        [
                            json.dumps(
                                {
                                    "_id": {"$oid": "legacy-1"},
                                    "idunplug_station": 8,
                                    "idplug_station": 9,
                                    "unplug_hourTime": {"$date": "2017-04-01T10:00:00Z"},
                                    "travel_time": 420,
                                }
                            ),
                            json.dumps(
                                {
                                    "_id": {"$oid": "legacy-2"},
                                    "idunplug_station": 9,
                                    "idplug_station": 8,
                                    "unplug_hourTime": {"$date": "2017-04-01T11:00:00Z"},
                                    "travel_time": 480,
                                }
                            ),
                        ]
                    ),
                )

            routes, stations, counters = build_models(input_dir)

        self.assertEqual(counters.valid_trips, 2)
        self.assertIn(("7", "8"), routes)
        self.assertIn(("8", "7"), routes)
        self.assertIn("7", stations)

    def test_deduplicates_legacy_rows_by_stable_id(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = Path(temp_dir)
            _write_station_catalog(input_dir, "202001", [(1, "10", "Origin"), (2, "20", "Destination")])
            trip = {
                "_id": {"$oid": "same-id"},
                "idunplug_station": 1,
                "idplug_station": 2,
                "unplug_hourTime": {"$date": "2020-01-01T10:00:00Z"},
                "travel_time": 300,
            }
            with zipfile.ZipFile(input_dir / "202001_movements.zip", "w") as archive:
                archive.writestr(
                    "202001_movements.json",
                    json.dumps(trip) + "\n" + json.dumps(trip) + "\n",
                )

            routes, _, counters = build_models(input_dir)

        self.assertEqual(routes[("10", "20")].count, 1)
        self.assertEqual(counters.duplicate_trips_skipped, 1)

    def test_prefers_csv_when_csv_and_legacy_cover_same_month(self):
        sources = [
            DataSource(Path("legacy.zip"), "202106_movements.json", "202106", "legacy_json", "zip"),
            DataSource(Path("modern.zip"), "trips_21_06_June.csv", "202106", "csv", "zip"),
        ]

        selected, skipped = select_trip_sources(sources)

        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0].source_format, "csv")
        self.assertEqual(skipped, 1)

    def test_discovers_direct_and_archived_legacy_sources_once_per_period(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = Path(temp_dir)
            direct = input_dir / "201704_Usage_Bicimad.json"
            direct.write_text("{}\n", encoding="utf-8")
            with zipfile.ZipFile(input_dir / "201704_Usage_Bicimad.zip", "w") as archive:
                archive.writestr("201704_Usage_Bicimad.json", "{}\n")

            trips, _ = discover_sources(input_dir)
            selected, skipped = select_trip_sources(trips)

        self.assertEqual(len(trips), 2)
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0].archive_type, "direct")
        self.assertEqual(skipped, 1)

    def test_rejects_legacy_trip_when_station_mapping_is_ambiguous(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            input_dir = Path(temp_dir)
            _write_station_catalog(input_dir, "202001", [(1, "10", "Origin"), (2, "20", "Destination")])
            _write_station_catalog(input_dir, "202002", [(1, "11", "Changed"), (2, "20", "Destination")])
            with zipfile.ZipFile(input_dir / "202001_movements.zip", "w") as archive:
                archive.writestr(
                    "202001_movements.json",
                    json.dumps(
                        {
                            "_id": {"$oid": "ambiguous"},
                            "idunplug_station": 1,
                            "idplug_station": 2,
                            "unplug_hourTime": {"$date": "2020-01-01T10:00:00Z"},
                            "travel_time": 300,
                        }
                    )
                    + "\n",
                )

            routes, _, counters = build_models(input_dir)

        self.assertFalse(routes)
        self.assertEqual(counters.unresolved_station_trips, 1)

    def test_repairs_published_october_2021_mixed_delimiters(self):
        row = (
            '"2021-10-01,trip-1,3455,1,5.35,""{\'type\':";\'Point\', '
            ';\'coordinates\': ;[-3.69,;"40.40]}"",,2021-10-01T00:00:08,'
            'STATION,STATION,""{\'type\':";\'Point\'}"",,2021-10-01T00:05:29,'
            '128,10,Palos; de ;la ;Frontera,243,22,Embajadores;191\r\n'
        )

        parsed = _parse_malformed_202110_row(row)

        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed["idTrip"], "trip-1")
        self.assertEqual(parsed["station_unlock"], "128")
        self.assertEqual(parsed["station_lock"], "243")
        self.assertEqual(parsed["unlock_station_name"], "Palos de la Frontera")
        self.assertEqual(parsed["lock_station_name"], "Embajadores 191")

    def test_reads_pretty_mongo_station_snapshot_with_number_int(self):
        payloads = list(
            _iter_station_payloads(
                b'''{
                  "stations": [
                    {"id": NumberInt(1), "number": "1a", "name": "Sol A"}
                  ]
                }'''
            )
        )

        self.assertEqual(len(payloads), 1)
        stations = payloads[0]["stations"]
        self.assertEqual(stations[0]["id"], 1)
        self.assertEqual(stations[0]["number"], "1a")


def _fixtures_dir() -> Path:
    return Path(__file__).parent / "fixtures"


def _write_station_catalog(
    input_dir: Path,
    period: str,
    stations: list[tuple[int, str, str]],
) -> None:
    with zipfile.ZipFile(input_dir / f"{period}-json.zip", "w") as archive:
        archive.writestr(
            f"{period}.json",
            json.dumps(
                {
                    "stations": [
                        {"id": station_id, "number": code, "name": name}
                        for station_id, code, name in stations
                    ]
                }
            )
            + "\n",
        )


if __name__ == "__main__":
    unittest.main()
