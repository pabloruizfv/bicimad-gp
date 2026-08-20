#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import io
import json
import math
import re
import sqlite3
import subprocess
import zipfile
from array import array
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import BinaryIO, Iterable, Iterator, TextIO

MODEL_FAMILY = "empirical_histogram"
MODEL_VERSION = "bicimad-opendata-v4"
MIN_DURATION_SECONDS = 60
MAX_DURATION_SECONDS = 4 * 60 * 60
BIN_COUNT = 32

_STATION_CODE_RE = re.compile(r"^\s*(\d+\s*[a-z]?)\s*-\s*(.+?)\s*$", re.I)


@dataclass
class IngestCounters:
    files_total: int = 0
    files_discovered: int = 0
    duplicate_sources_skipped: int = 0
    station_catalogs: int = 0
    rows_total: int = 0
    valid_trips: int = 0
    rejected_trips: int = 0
    unresolved_station_trips: int = 0
    duplicate_trips_skipped: int = 0


@dataclass(frozen=True)
class DataSource:
    path: Path
    member_name: str | None = None
    period: str = ""
    source_format: str = "csv"
    archive_type: str = "direct"

    @property
    def display_name(self) -> str:
        if self.member_name is None:
            return str(self.path)
        return f"{self.path}!{self.member_name}"


CsvSource = DataSource


@dataclass(frozen=True)
class StationReference:
    public_code: str
    name: str
    latitude: float | None = None
    longitude: float | None = None


class StationReferenceResolver:
    def __init__(self) -> None:
        self._by_id_and_name: dict[tuple[str, str], dict[str, StationReference]] = {}
        self._by_id: dict[str, dict[str, StationReference]] = {}
        self._by_name: dict[str, dict[str, StationReference]] = {}

    def remember(
        self,
        *,
        original_id: object,
        public_code: object,
        name: object,
        latitude: object = None,
        longitude: object = None,
    ) -> None:
        station_id = normalize_identifier(original_id)
        code = normalize_public_code(public_code)
        station_name = clean_text(name)
        normalized_name = normalize_station_name(station_name)
        if station_id is None or code is None or not station_name or not normalized_name:
            return

        reference = StationReference(
            public_code=code,
            name=station_name,
            latitude=parse_optional_float(latitude),
            longitude=parse_optional_float(longitude),
        )
        self._by_id_and_name.setdefault((station_id, normalized_name), {})[
            code
        ] = reference
        self._by_id.setdefault(station_id, {})[code] = reference
        self._by_name.setdefault(normalized_name, {})[code] = reference

    def resolve(
        self,
        *,
        station_id: str | None,
        station_name: str | None,
    ) -> tuple[str, str] | None:
        original_id = normalize_identifier(station_id)
        clean_name = clean_text(station_name)
        normalized_name = normalize_station_name(clean_name)

        if original_id is not None and normalized_name:
            exact = self._by_id_and_name.get((original_id, normalized_name))
            if exact is not None and len(exact) == 1:
                reference = next(iter(exact.values()))
                return reference.public_code, clean_name or reference.name

        if normalized_name:
            by_name = self._by_name.get(normalized_name)
            if by_name is not None and len(by_name) == 1:
                reference = next(iter(by_name.values()))
                return reference.public_code, clean_name or reference.name

        if original_id is not None:
            by_id = self._by_id.get(original_id)
            if by_id is not None and len(by_id) == 1:
                reference = next(iter(by_id.values()))
                return reference.public_code, clean_name or reference.name

        return None

    def resolve_legacy_id(self, station_id: object) -> StationReference | None:
        original_id = normalize_identifier(station_id)
        if original_id is None:
            return None
        candidates = self._by_id.get(original_id)
        if candidates is None or len(candidates) != 1:
            return None
        return next(iter(candidates.values()))

    @property
    def unambiguous_id_count(self) -> int:
        return sum(len(values) == 1 for values in self._by_id.values())

    @property
    def ambiguous_id_count(self) -> int:
        return sum(len(values) > 1 for values in self._by_id.values())


class RouteAccumulator:
    def __init__(self) -> None:
        self.count = 0
        self.best_seconds = math.inf
        self.durations_seconds = array("d")
        self.first_trip_at: str | None = None
        self.last_trip_at: str | None = None
        self.origin_name = ""
        self.destination_name = ""

    def add(self, duration_seconds: float, started_at: datetime) -> None:
        self.count += 1
        self.best_seconds = min(self.best_seconds, duration_seconds)
        self.durations_seconds.append(duration_seconds)

        timestamp = started_at.isoformat()
        if self.first_trip_at is None or timestamp < self.first_trip_at:
            self.first_trip_at = timestamp
        if self.last_trip_at is None or timestamp > self.last_trip_at:
            self.last_trip_at = timestamp

    def histogram(self) -> tuple[float, int, int, list[float], list[int]]:
        if not self.durations_seconds:
            return math.nan, 0, 0, [], []

        sorted_durations = sorted(self.durations_seconds)
        q1_seconds = percentile(sorted_durations, 0.25)
        q3_seconds = percentile(sorted_durations, 0.75)
        p99_seconds = percentile(sorted_durations, 0.99)
        iqr_seconds = q3_seconds - q1_seconds
        upper_cutoff_seconds = min(p99_seconds, q3_seconds + 3 * iqr_seconds)
        if (
            not math.isfinite(self.best_seconds)
            or not math.isfinite(upper_cutoff_seconds)
            or upper_cutoff_seconds <= self.best_seconds
        ):
            outlier_count = sum(
                duration > upper_cutoff_seconds for duration in sorted_durations
            )
            return upper_cutoff_seconds, len(sorted_durations) - outlier_count, outlier_count, [], []

        width = (upper_cutoff_seconds - self.best_seconds) / BIN_COUNT
        bin_edges = [self.best_seconds + width * index for index in range(BIN_COUNT + 1)]
        bin_counts = [0 for _ in range(BIN_COUNT)]
        outlier_count = 0

        for duration in sorted_durations:
            if duration > upper_cutoff_seconds:
                outlier_count += 1
                continue
            index = int((duration - self.best_seconds) / width)
            if index >= BIN_COUNT:
                index = BIN_COUNT - 1
            if index < 0:
                index = 0
            bin_counts[index] += 1

        return (
            upper_cutoff_seconds,
            sum(bin_counts),
            outlier_count,
            bin_edges,
            bin_counts,
        )


def percentile(sorted_values: list[float] | array, probability: float) -> float:
    if not sorted_values:
        return math.nan
    if probability <= 0:
        return sorted_values[0]
    if probability >= 1:
        return sorted_values[-1]

    position = (len(sorted_values) - 1) * probability
    lower_index = math.floor(position)
    upper_index = math.ceil(position)
    if lower_index == upper_index:
        return sorted_values[lower_index]
    lower = sorted_values[lower_index]
    upper = sorted_values[upper_index]
    return lower + (upper - lower) * (position - lower_index)


def clean_text(value: object) -> str:
    return str(value or "").strip().strip("'\"").strip()


def normalize_identifier(value: object) -> str | None:
    text = clean_text(value)
    return text if text else None


def parse_optional_float(value: object) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def normalize_public_code(value: object) -> str | None:
    text = clean_text(value)
    match = re.match(r"^0*(\d+)\s*([a-z]?)", text, re.I)
    if match is None:
        return None
    return str(int(match.group(1))) + match.group(2).lower()


def normalize_station_name(value: object) -> str:
    text = clean_text(value).lower()
    text = re.sub(r"^\s*\d+\s*-\s*", "", text)
    text = (
        text.replace("á", "a")
        .replace("à", "a")
        .replace("ä", "a")
        .replace("â", "a")
        .replace("é", "e")
        .replace("è", "e")
        .replace("ë", "e")
        .replace("ê", "e")
        .replace("í", "i")
        .replace("ì", "i")
        .replace("ï", "i")
        .replace("î", "i")
        .replace("ó", "o")
        .replace("ò", "o")
        .replace("ö", "o")
        .replace("ô", "o")
        .replace("ú", "u")
        .replace("ù", "u")
        .replace("ü", "u")
        .replace("û", "u")
        .replace("ñ", "n")
    )
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", text)).strip()


def extract_station_code(value: str | None) -> tuple[str, str] | None:
    normalized = clean_text(value)
    if not normalized:
        return None
    match = _STATION_CODE_RE.match(normalized)
    if match is None:
        return None
    code = normalize_public_code(match.group(1))
    if code is None:
        return None
    return code, match.group(2).strip()


def resolve_station_code(
    station_name: str | None,
    station_id: str | None,
    reference_resolver: StationReferenceResolver | None = None,
) -> tuple[str, str] | None:
    parsed_from_name = extract_station_code(station_name)
    if parsed_from_name is not None:
        return parsed_from_name

    if reference_resolver is not None:
        resolved = reference_resolver.resolve(
            station_id=station_id,
            station_name=station_name,
        )
        if resolved is not None:
            return resolved

    fallback_id = normalize_public_code(station_id)
    if fallback_id is None:
        return None

    normalized_name = clean_text(station_name)
    return fallback_id, normalized_name


def parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    raw = value.strip().strip("'\"")
    if not raw:
        return None
    raw = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", raw)
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_coordinates(value: str | None) -> tuple[float | None, float | None]:
    if not value:
        return None, None
    try:
        parsed = ast.literal_eval(value.strip())
    except (ValueError, SyntaxError):
        return None, None
    if not isinstance(parsed, dict):
        return None, None
    coordinates = parsed.get("coordinates")
    if not isinstance(coordinates, list) or len(coordinates) < 2:
        return None, None
    try:
        longitude = float(coordinates[0])
        latitude = float(coordinates[1])
    except (TypeError, ValueError):
        return None, None
    return latitude, longitude


_COMPACT_PERIOD_RE = re.compile(r"(?<!\d)(20\d{2})(0[1-9]|1[0-2])(?!\d)")
_TRIPS_PERIOD_RE = re.compile(r"trips[_-](\d{2})[_-](0[1-9]|1[0-2])", re.I)


def extract_period(*values: str) -> str | None:
    for value in values:
        compact = _COMPACT_PERIOD_RE.search(value)
        if compact is not None:
            return compact.group(1) + compact.group(2)
        trips = _TRIPS_PERIOD_RE.search(value)
        if trips is not None:
            return "20" + trips.group(1) + trips.group(2)
    return None


def _is_ignored_member(name: str) -> bool:
    path = Path(name)
    return path.name.startswith("._") or "__MACOSX" in path.parts


def _is_trip_json(name: str) -> bool:
    lowered = name.lower()
    return "usage" in lowered or "movement" in lowered


def discover_sources(input_dir: Path) -> tuple[list[DataSource], list[DataSource]]:
    trip_sources: list[DataSource] = []
    station_sources: list[DataSource] = []

    for path in sorted(input_dir.rglob("*")):
        if not path.is_file() or path.name.startswith("._"):
            continue
        suffix = path.suffix.lower()
        if suffix == ".csv":
            period = extract_period(path.name, str(path.parent))
            trip_sources.append(
                DataSource(path, period=period or f"fixture:{path.as_posix()}")
            )
        elif suffix == ".json":
            period = extract_period(path.name, str(path.parent))
            if not period:
                continue
            target = trip_sources if _is_trip_json(path.name) else station_sources
            target.append(
                DataSource(
                    path,
                    period=period,
                    source_format="legacy_json" if target is trip_sources else "station_json",
                )
            )
        elif suffix == ".rar":
            period = extract_period(path.name, str(path.parent))
            if period:
                station_sources.append(
                    DataSource(
                        path,
                        period=period,
                        source_format="station_json",
                        archive_type="rar",
                    )
                )
        elif suffix == ".zip":
            try:
                with zipfile.ZipFile(path) as archive:
                    for member in archive.infolist():
                        if member.is_dir() or _is_ignored_member(member.filename):
                            continue
                        member_suffix = Path(member.filename).suffix.lower()
                        if member_suffix not in {".csv", ".json"}:
                            continue
                        period = extract_period(member.filename, path.name)
                        if not period:
                            continue
                        if member_suffix == ".csv":
                            trip_sources.append(
                                DataSource(
                                    path,
                                    member.filename,
                                    period,
                                    "csv",
                                    "zip",
                                )
                            )
                        elif _is_trip_json(member.filename):
                            trip_sources.append(
                                DataSource(
                                    path,
                                    member.filename,
                                    period,
                                    "legacy_json",
                                    "zip",
                                )
                            )
                        else:
                            station_sources.append(
                                DataSource(
                                    path,
                                    member.filename,
                                    period,
                                    "station_json",
                                    "zip",
                                )
                            )
            except zipfile.BadZipFile:
                continue

    return trip_sources, station_sources


def select_trip_sources(sources: Iterable[DataSource]) -> tuple[list[DataSource], int]:
    by_period: dict[str, list[DataSource]] = {}
    for source in sources:
        by_period.setdefault(source.period, []).append(source)

    selected: list[DataSource] = []
    skipped = 0
    for period, candidates in sorted(by_period.items()):
        # Prefer the normalized CSV when both publication formats cover a month.
        winner = min(
            candidates,
            key=lambda source: (
                0 if source.source_format == "csv" else 1,
                0 if source.archive_type == "direct" else 1,
                source.display_name.lower(),
            ),
        )
        selected.append(winner)
        skipped += len(candidates) - 1
    return selected, skipped


def find_csv_sources(input_dir: Path) -> list[CsvSource]:
    trip_sources, _ = discover_sources(input_dir)
    return sorted(
        (source for source in trip_sources if source.source_format == "csv"),
        key=lambda source: source.display_name,
    )


@contextmanager
def open_binary_source(source: DataSource) -> Iterator[BinaryIO]:
    if source.archive_type == "direct":
        with source.path.open("rb") as handle:
            yield handle
        return
    if source.archive_type == "zip":
        if source.member_name is None:
            raise ValueError("ZIP source is missing its member name")
        with zipfile.ZipFile(source.path) as archive:
            with archive.open(source.member_name) as handle:
                yield handle
        return
    if source.archive_type == "rar":
        listing = subprocess.run(
            ["tar", "-tf", str(source.path)],
            capture_output=True,
            check=False,
        )
        if listing.returncode != 0:
            raise RuntimeError(
                f"Cannot read RAR station catalog with tar: {source.path}"
            )
        members = [
            line.decode("utf-8", "replace").strip()
            for line in listing.stdout.splitlines()
            if line.strip()
            and line.decode("utf-8", "replace").lower().endswith(".json")
            and not _is_ignored_member(line.decode("utf-8", "replace").strip())
        ]
        if not members:
            raise RuntimeError(f"RAR station catalog has no JSON member: {source.path}")
        extracted = subprocess.run(
            ["tar", "-xOf", str(source.path), members[0]],
            capture_output=True,
            check=False,
        )
        if extracted.returncode != 0:
            raise RuntimeError(
                f"Cannot extract RAR station catalog with tar: {source.path}"
            )
        with io.BytesIO(extracted.stdout) as handle:
            yield handle
        return
    raise ValueError(f"Unsupported archive type: {source.archive_type}")


def _decode_json_bytes(raw: bytes) -> str:
    for encoding in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace")


def _iter_json_values(raw: bytes) -> Iterator[object]:
    text = _decode_json_bytes(raw)
    # July/August 2018 station exports use Mongo shell NumberInt(...).
    text = re.sub(r"\bNumber(?:Int|Long)\(\s*(-?\d+)\s*\)", r"\1", text)
    decoder = json.JSONDecoder()
    position = 0
    while position < len(text):
        while position < len(text) and text[position].isspace():
            position += 1
        if position >= len(text):
            return
        try:
            value, position = decoder.raw_decode(text, position)
        except json.JSONDecodeError:
            return
        yield value


def _iter_station_payloads(raw: bytes) -> Iterator[dict[str, object]]:
    # Fast path for the normal NDJSON snapshots.
    parsed_lines = 0
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            value = json.loads(_decode_json_bytes(line))
        except json.JSONDecodeError:
            parsed_lines = 0
            break
        if isinstance(value, dict):
            parsed_lines += 1
            yield value
    if parsed_lines:
        return
    yield from (
        value for value in _iter_json_values(raw) if isinstance(value, dict)
    )


def build_station_reference_resolver(
    input_dir: Path,
) -> StationReferenceResolver:
    resolver, _ = build_station_reference_data(input_dir)
    return resolver


def build_station_reference_data(
    input_dir: Path,
) -> tuple[StationReferenceResolver, int]:
    resolver = StationReferenceResolver()
    _, station_sources = discover_sources(input_dir)
    for source in sorted(station_sources, key=lambda item: item.display_name):
        with open_binary_source(source) as handle:
            raw = handle.read()
        last_payload: dict[str, object] | None = None
        for payload in _iter_station_payloads(raw):
            if isinstance(payload.get("stations"), list):
                last_payload = payload
        if last_payload is None:
            continue
        stations = last_payload["stations"]
        assert isinstance(stations, list)
        for station in stations:
            if not isinstance(station, dict):
                continue
            resolver.remember(
                original_id=station.get("id"),
                public_code=station.get("number"),
                name=station.get("name"),
                latitude=station.get("latitude"),
                longitude=station.get("longitude"),
            )
    return resolver, len(station_sources)


@contextmanager
def open_csv_source(source: CsvSource) -> Iterator[TextIO]:
    with open_binary_source(source) as raw:
        with io.TextIOWrapper(
            raw,
            encoding="utf-8-sig",
            errors="replace",
            newline="",
        ) as handle:
            yield handle


def detect_csv_delimiter(header: str) -> str:
    comma_count = header.count(",")
    semicolon_count = header.count(";")
    return "," if comma_count > semicolon_count else ";"


def _iter_csv_rows(handle: TextIO) -> Iterator[dict[str, str]]:
    header = handle.readline()
    if not header:
        return
    delimiter = detect_csv_delimiter(header)
    expected_fields = {
        "unlock_date",
        "lock_date",
        "station_unlock",
        "station_lock",
    }
    fieldnames = next(csv.reader([header], delimiter=delimiter), [])
    if expected_fields.issubset(fieldnames):
        yield from csv.DictReader(handle, fieldnames=fieldnames, delimiter=delimiter)
        return

    # The published October 2021 file mixes comma and semicolon separators.
    # Recover only the fields needed by the model using timestamp anchors.
    for line in handle:
        repaired = _parse_malformed_202110_row(line)
        if repaired is not None:
            yield repaired


_ISO_TIMESTAMP_RE = re.compile(r"20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")


def _parse_malformed_202110_row(line: str) -> dict[str, str] | None:
    timestamps = list(_ISO_TIMESTAMP_RE.finditer(line))
    # A timestamp can also be embedded in idTrip; the final two are unlock/lock.
    if len(timestamps) < 2:
        return None
    unlock_timestamp = timestamps[-2]
    lock_timestamp = timestamps[-1]
    between_timestamps = line[unlock_timestamp.end() : lock_timestamp.start()]
    type_fields = between_timestamps.lstrip(",").split(",", 2)
    if len(type_fields) < 2:
        return None
    tail = line[lock_timestamp.end() :].lstrip(",")
    leading_tail = tail.split(",", 2)
    if len(leading_tail) != 3:
        return None
    station_unlock, dock_unlock, station_tail = leading_tail
    tail_parts = station_tail.strip().strip('"').rsplit(",", 3)
    if len(tail_parts) != 4:
        return None
    origin_name, station_lock, dock_lock, destination_name = tail_parts
    start = line.lstrip('"').split(",", 3)
    trip_id = start[1].strip() if len(start) > 1 else ""
    return {
        "idTrip": trip_id,
        "unlock_date": unlock_timestamp.group(),
        "lock_date": lock_timestamp.group(),
        "locktype": type_fields[0].strip(" ;\""),
        "unlocktype": type_fields[1].strip(" ;\""),
        "station_unlock": station_unlock.strip(" ;\""),
        "dock_unlock": dock_unlock.strip(" ;\""),
        "unlock_station_name": re.sub(r"\s*;\s*", " ", origin_name).strip(),
        "station_lock": station_lock.strip(" ;\""),
        "dock_lock": dock_lock.strip(" ;\""),
        "lock_station_name": re.sub(
            r"\s*;\s*", " ", destination_name
        ).strip(),
    }


def build_models(input_dir: Path) -> tuple[dict[tuple[str, str], RouteAccumulator], dict[str, dict[str, object]], IngestCounters]:
    routes: dict[tuple[str, str], RouteAccumulator] = {}
    stations: dict[str, dict[str, object]] = {}
    counters = IngestCounters()
    discovered_trips, _ = discover_sources(input_dir)
    selected_sources, skipped_sources = select_trip_sources(discovered_trips)
    reference_resolver, station_catalog_count = build_station_reference_data(input_dir)
    counters.files_discovered = len(discovered_trips)
    counters.files_total = len(selected_sources)
    counters.duplicate_sources_skipped = skipped_sources
    counters.station_catalogs = station_catalog_count

    for source_index, source in enumerate(selected_sources, start=1):
        print(
            f"Processing trips {source_index}/{len(selected_sources)}: "
            f"{source.period} ({source.source_format})",
            flush=True,
        )
        seen_trip_ids: set[str] = set()
        rows = _read_source_rows(source, reference_resolver)
        for source_trip_id, row, result, station_details in rows:
            counters.rows_total += 1
            if source_trip_id:
                if source_trip_id in seen_trip_ids:
                    counters.duplicate_trips_skipped += 1
                    continue
                seen_trip_ids.add(source_trip_id)
            if result is None:
                counters.rejected_trips += 1
                if station_details == "unresolved_station":
                    counters.unresolved_station_trips += 1
                continue

            (
                origin_code,
                origin_name,
                destination_code,
                destination_name,
                duration_seconds,
                started_at,
            ) = result
            route_key = (origin_code, destination_code)
            stats = routes.setdefault(route_key, RouteAccumulator())
            stats.origin_name = origin_name
            stats.destination_name = destination_name
            stats.add(duration_seconds, started_at)
            counters.valid_trips += 1

            _remember_station(
                stations,
                code=origin_code,
                name=origin_name,
                original_id=row.get("station_unlock"),
                coordinates=row.get("geolocation_unlock"),
            )
            _remember_station(
                stations,
                code=destination_code,
                name=destination_name,
                original_id=row.get("station_lock"),
                coordinates=row.get("geolocation_lock"),
            )

    return routes, stations, counters


def _read_source_rows(
    source: DataSource,
    resolver: StationReferenceResolver,
) -> Iterator[
    tuple[
        str | None,
        dict[str, str],
        tuple[str, str, str, str, float, datetime] | None,
        str | None,
    ]
]:
    if source.source_format == "csv":
        with open_csv_source(source) as handle:
            for row in _iter_csv_rows(handle):
                result, reason = _parse_valid_csv_trip(row, resolver)
                yield normalize_identifier(row.get("idTrip")), row, result, reason
        return

    with open_binary_source(source) as raw:
        for line in raw:
            if not line.strip():
                continue
            try:
                payload = json.loads(_decode_json_bytes(line))
            except json.JSONDecodeError:
                yield None, {}, None, "malformed"
                continue
            if not isinstance(payload, dict):
                yield None, {}, None, "malformed"
                continue
            source_trip_id = _legacy_trip_id(payload)
            result, reason, row = _parse_valid_legacy_trip(payload, resolver)
            yield source_trip_id, row, result, reason


def _legacy_trip_id(payload: dict[str, object]) -> str | None:
    value = payload.get("_id")
    if isinstance(value, dict):
        return normalize_identifier(value.get("$oid"))
    return normalize_identifier(value)


def _legacy_timestamp(value: object) -> datetime | None:
    if isinstance(value, dict):
        value = value.get("$date")
    return parse_timestamp(clean_text(value))


def _parse_valid_legacy_trip(
    payload: dict[str, object],
    resolver: StationReferenceResolver,
) -> tuple[
    tuple[str, str, str, str, float, datetime] | None,
    str | None,
    dict[str, str],
]:
    origin = resolver.resolve_legacy_id(payload.get("idunplug_station"))
    destination = resolver.resolve_legacy_id(payload.get("idplug_station"))
    row = {
        "station_unlock": clean_text(payload.get("idunplug_station")),
        "station_lock": clean_text(payload.get("idplug_station")),
    }
    if origin is None or destination is None:
        return None, "unresolved_station", row
    if origin.public_code == destination.public_code:
        return None, "same_station", row
    started_at = _legacy_timestamp(payload.get("unplug_hourTime"))
    duration_seconds = parse_optional_float(payload.get("travel_time"))
    if started_at is None or duration_seconds is None:
        return None, "malformed", row
    if duration_seconds < MIN_DURATION_SECONDS or duration_seconds > MAX_DURATION_SECONDS:
        return None, "duration", row
    return (
        (
            origin.public_code,
            origin.name,
            destination.public_code,
            destination.name,
            duration_seconds,
            started_at,
        ),
        None,
        row,
    )


def _parse_valid_trip(
    row: dict[str, str],
    reference_resolver: StationReferenceResolver,
) -> tuple[str, str, str, str, float, datetime] | None:
    result, _ = _parse_valid_csv_trip(row, reference_resolver)
    return result


def _parse_valid_csv_trip(
    row: dict[str, str],
    reference_resolver: StationReferenceResolver,
) -> tuple[tuple[str, str, str, str, float, datetime] | None, str | None]:
    if not row or not any((value or "").strip() for value in row.values()):
        return None, "malformed"
    if row.get("unlocktype") != "STATION" or row.get("locktype") != "STATION":
        return None, "not_station"

    origin = resolve_station_code(
        row.get("unlock_station_name"),
        row.get("station_unlock"),
        reference_resolver,
    )
    destination = resolve_station_code(
        row.get("lock_station_name"),
        row.get("station_lock"),
        reference_resolver,
    )
    if origin is None or destination is None:
        return None, "unresolved_station"
    origin_code, origin_name = origin
    destination_code, destination_name = destination
    if origin_code == destination_code:
        return None, "same_station"

    unlocked_at = parse_timestamp(row.get("unlock_date"))
    locked_at = parse_timestamp(row.get("lock_date"))
    if unlocked_at is None or locked_at is None:
        return None, "malformed"
    duration_seconds = (locked_at - unlocked_at).total_seconds()
    if duration_seconds < MIN_DURATION_SECONDS or duration_seconds > MAX_DURATION_SECONDS:
        return None, "duration"

    return (
        (
            origin_code,
            origin_name,
            destination_code,
            destination_name,
            duration_seconds,
            unlocked_at,
        ),
        None,
    )


def _remember_station(
    stations: dict[str, dict[str, object]],
    *,
    code: str,
    name: str,
    original_id: str | None,
    coordinates: str | None,
) -> None:
    latitude, longitude = parse_coordinates(coordinates)
    existing = stations.get(code)
    if existing is None:
        stations[code] = {
            "code": code,
            "name": name,
            "original_ids": {original_id} if original_id else set(),
            "latitude": latitude,
            "longitude": longitude,
        }
        return

    if original_id:
        existing["original_ids"].add(original_id)  # type: ignore[union-attr]
    if existing.get("latitude") is None and latitude is not None:
        existing["latitude"] = latitude
    if existing.get("longitude") is None and longitude is not None:
        existing["longitude"] = longitude


def write_sqlite(
    output_path: Path,
    routes: dict[tuple[str, str], RouteAccumulator],
    stations: dict[str, dict[str, object]],
    counters: IngestCounters,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    connection = sqlite3.connect(output_path)
    try:
        cursor = connection.cursor()
        cursor.executescript(
            """
            PRAGMA journal_mode = OFF;
            CREATE TABLE metadata (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE stations (
              station_code TEXT PRIMARY KEY,
              station_name TEXT NOT NULL,
              latitude REAL,
              longitude REAL,
              original_ids TEXT NOT NULL
            );
            CREATE TABLE route_models (
              origin_station_code TEXT NOT NULL,
              destination_station_code TEXT NOT NULL,
              origin_station_name TEXT NOT NULL,
              destination_station_name TEXT NOT NULL,
              total_count INTEGER NOT NULL,
              displayed_count INTEGER NOT NULL,
              outlier_count INTEGER NOT NULL,
              upper_cutoff_seconds REAL NOT NULL,
              best_seconds REAL NOT NULL,
              bin_edges TEXT NOT NULL,
              bin_counts TEXT NOT NULL,
              first_trip_at TEXT NOT NULL,
              last_trip_at TEXT NOT NULL,
              model_family TEXT NOT NULL,
              model_version TEXT NOT NULL,
              PRIMARY KEY (origin_station_code, destination_station_code)
            );
            """
        )
        cursor.executemany(
            """
            INSERT INTO route_models (
              origin_station_code, destination_station_code,
              origin_station_name, destination_station_name,
              total_count, displayed_count, outlier_count,
              upper_cutoff_seconds, best_seconds,
              bin_edges, bin_counts,
              first_trip_at, last_trip_at,
              model_family, model_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    origin,
                    destination,
                    stats.origin_name,
                    stats.destination_name,
                    stats.count,
                    displayed_count,
                    outlier_count,
                    upper_cutoff_seconds,
                    stats.best_seconds,
                    json.dumps(bin_edges, separators=(",", ":")),
                    json.dumps(bin_counts, separators=(",", ":")),
                    stats.first_trip_at,
                    stats.last_trip_at,
                    MODEL_FAMILY,
                    MODEL_VERSION,
                )
                for (origin, destination), stats in routes.items()
                for upper_cutoff_seconds, displayed_count, outlier_count, bin_edges, bin_counts in [
                    stats.histogram()
                ]
            ],
        )
        cursor.executemany(
            """
            INSERT INTO stations (
              station_code, station_name, latitude, longitude, original_ids
            ) VALUES (?, ?, ?, ?, ?)
            """,
            [
                (
                    station["code"],
                    station["name"],
                    station["latitude"],
                    station["longitude"],
                    ",".join(sorted(station["original_ids"])),
                )
                for station in stations.values()
            ],
        )
        metadata = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "model_family": MODEL_FAMILY,
            "model_version": MODEL_VERSION,
            "files_total": str(counters.files_total),
            "files_discovered": str(counters.files_discovered),
            "duplicate_sources_skipped": str(counters.duplicate_sources_skipped),
            "station_catalogs": str(counters.station_catalogs),
            "rows_total": str(counters.rows_total),
            "valid_trips": str(counters.valid_trips),
            "rejected_trips": str(counters.rejected_trips),
            "unresolved_station_trips": str(counters.unresolved_station_trips),
            "duplicate_trips_skipped": str(counters.duplicate_trips_skipped),
            "routes_created": str(len(routes)),
        }
        cursor.executemany(
            "INSERT INTO metadata (key, value) VALUES (?, ?)",
            sorted(metadata.items()),
        )
        connection.commit()
        cursor.execute("VACUUM")
    finally:
        connection.close()


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)

    if not args.input.exists() or not args.input.is_dir():
        parser.error(f"Input directory does not exist: {args.input}")

    routes, stations, counters = build_models(args.input)
    write_sqlite(args.output, routes, stations, counters)
    digest = hashlib.sha256()
    with args.output.open("rb") as database_file:
        for chunk in iter(lambda: database_file.read(1024 * 1024), b""):
            digest.update(chunk)
    manifest_path = args.output.with_name(
        f"{args.output.stem}.manifest.json"
    )
    manifest_path.write_text(
        json.dumps(
            {
                "version": MODEL_VERSION,
                "size": args.output.stat().st_size,
                "sha256": digest.hexdigest(),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Trip sources discovered: {counters.files_discovered}")
    print(f"Files processed: {counters.files_total}")
    print(f"Duplicate sources skipped: {counters.duplicate_sources_skipped}")
    print(f"Station catalogs processed: {counters.station_catalogs}")
    print(f"Valid trips: {counters.valid_trips}")
    print(f"Rejected trips: {counters.rejected_trips}")
    print(f"Unresolved station trips: {counters.unresolved_station_trips}")
    print(f"Duplicate trips skipped: {counters.duplicate_trips_skipped}")
    print(f"Routes created: {len(routes)}")
    print(f"Output: {args.output}")
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
