#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin

DEFAULT_GBFS_URL = (
    "https://madrid.publicbikesystem.net/customer/gbfs/v2/es/station_information"
)


def normalize_public_code(value: object) -> str | None:
    text = str(value or "").strip()
    if not text:
        return None
    match = re.match(r"^(\d+)", text)
    if match:
        return str(int(match.group(1)))
    return None


def station_from_gbfs(raw: dict[str, object]) -> dict[str, object] | None:
    station_id = str(raw.get("station_id") or raw.get("id") or "").strip()
    name = str(raw.get("name") or "").strip()
    public_code = normalize_public_code(name)
    if public_code is None:
        public_code = normalize_public_code(raw.get("short_name"))
    try:
        latitude = float(raw["lat"])
        longitude = float(raw["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    if not station_id or not name or public_code is None:
        return None
    return {
        "id": station_id,
        "public_code": public_code,
        "name": name,
        "latitude": latitude,
        "longitude": longitude,
    }


def station_from_opendata(raw: dict[str, object]) -> dict[str, object] | None:
    station_id = str(raw.get("id") or "").strip()
    public_code = normalize_public_code(raw.get("number")) or normalize_public_code(
        raw.get("name")
    )
    name = str(raw.get("name") or "").strip()
    try:
        latitude = float(raw["latitude"])
        longitude = float(raw["longitude"])
    except (KeyError, TypeError, ValueError):
        return None
    if not station_id or not name or public_code is None:
        return None
    return {
        "id": station_id,
        "public_code": public_code,
        "name": name,
        "latitude": latitude,
        "longitude": longitude,
    }


def load_from_gbfs(url: str) -> list[dict[str, object]]:
    payload = _read_json(url)
    stations = _stations_from_payload(payload)
    if not isinstance(stations, list) or not stations:
        station_information_url = _find_station_information_url(payload)
        if station_information_url is None:
            raise ValueError("GBFS feed does not reference station_information")
        payload = _read_json(urljoin(url, station_information_url))
        stations = _stations_from_payload(payload)
    if not isinstance(stations, list):
        raise ValueError("GBFS station_information does not contain stations")
    return _deduplicate(
        station for item in stations if isinstance(item, dict) for station in [station_from_gbfs(item)] if station
    )


def _read_json(url: str) -> dict[str, object]:
    with urllib.request.urlopen(url, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("GBFS response is not an object")
    return payload


def _stations_from_payload(payload: dict[str, object]) -> object:
    data = payload.get("data")
    if not isinstance(data, dict):
        return None
    return data.get("stations")


def _find_station_information_url(value: object) -> str | None:
    if isinstance(value, dict):
        name = str(value.get("name") or "").lower()
        candidate = value.get("url")
        if "station_information" in name and isinstance(candidate, str):
            return candidate
        for item in value.values():
            found = _find_station_information_url(item)
            if found is not None:
                return found
    elif isinstance(value, list):
        for item in value:
            found = _find_station_information_url(item)
            if found is not None:
                return found
    return None


def load_from_opendata(input_dir: Path) -> list[dict[str, object]]:
    snapshots: list[tuple[Path, str, bytes]] = []
    for zip_path in sorted(input_dir.rglob("*json.zip")):
        with zipfile.ZipFile(zip_path) as archive:
            for member in archive.infolist():
                if member.is_dir() or not member.filename.lower().endswith(".json"):
                    continue
                with archive.open(member) as handle:
                    last_line = None
                    for line in handle:
                        if line.strip():
                            last_line = line
                    if last_line is not None:
                        snapshots.append((zip_path, member.filename, last_line))

    if not snapshots:
        raise ValueError("No station snapshots found")

    _, _, raw_payload = snapshots[-1]
    payload = json.loads(raw_payload.decode("utf-8"))
    stations = payload.get("stations", [])
    if not isinstance(stations, list):
        raise ValueError("Open Data station snapshot does not contain stations")
    return _deduplicate(
        station for item in stations if isinstance(item, dict) for station in [station_from_opendata(item)] if station
    )


def _deduplicate(stations: Iterable[dict[str, object]]) -> list[dict[str, object]]:
    by_id: dict[str, dict[str, object]] = {}
    for station in stations:
        by_id[str(station["id"])] = station
    return sorted(by_id.values(), key=lambda station: str(station["public_code"]).zfill(4))


def write_asset(output_path: Path, stations: list[dict[str, object]]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "bicimad_station_catalog",
        "stations": stations,
    }
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--gbfs-url", default=DEFAULT_GBFS_URL)
    parser.add_argument("--from-opendata", type=Path)
    args = parser.parse_args(argv)

    if args.from_opendata is not None:
        stations = load_from_opendata(args.from_opendata)
    else:
        stations = load_from_gbfs(args.gbfs_url)

    write_asset(args.output, stations)
    print(f"Stations: {len(stations)}")
    print(f"Output: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
