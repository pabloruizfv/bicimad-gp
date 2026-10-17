"""Generate a Supabase migration with the bundled station elevations.

The generated migration keeps the database-side fallback aligned with the
station snapshot shipped by the Flutter app. It never embeds user or trip data.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_PATH = ROOT / "assets" / "data" / "station_catalog_snapshot.json"


def _sql_text(value: object) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def _canonical_code(station: dict[str, object]) -> str:
    name = str(station["name"])
    match = re.match(r"^\s*0*(\d+)\s*([a-z]?)\s*-", name, re.IGNORECASE)
    if match:
        return f"{int(match.group(1))}{match.group(2).lower()}"

    public_code = str(station["public_code"]).strip().lower()
    match = re.fullmatch(r"0*(\d+)\s*([a-z]?)", public_code)
    if not match:
        raise ValueError(f"Station has no canonical public code: {station!r}")
    return f"{int(match.group(1))}{match.group(2).lower()}"


def _station_rows(snapshot: dict[str, object]) -> list[str]:
    stations = snapshot.get("stations")
    if not isinstance(stations, list) or not stations:
        raise ValueError("Station snapshot is empty")

    rows: list[str] = []
    seen_codes: set[str] = set()
    seen_ids: set[str] = set()
    grid_version = snapshot.get("elevation_grid_version")
    if not isinstance(grid_version, str) or not grid_version:
        raise ValueError("Station snapshot has no elevation grid version")

    for raw_station in stations:
        if not isinstance(raw_station, dict):
            raise ValueError("Invalid station entry")
        station = raw_station
        code = _canonical_code(station)
        station_id = str(station["id"])
        if code in seen_codes:
            raise ValueError(f"Duplicate canonical station code: {code}")
        if station_id in seen_ids:
            raise ValueError(f"Duplicate station id: {station_id}")
        seen_codes.add(code)
        seen_ids.add(station_id)

        elevation = station.get("elevation_meters")
        if not isinstance(elevation, (int, float)):
            raise ValueError(f"Station {station_id} has no elevation")
        latitude = float(station["latitude"])
        longitude = float(station["longitude"])
        rows.append(
            "  ("
            + ", ".join(
                (
                    _sql_text(code),
                    _sql_text(station_id),
                    _sql_text(station["name"]),
                    repr(latitude),
                    repr(longitude),
                    repr(float(elevation)),
                    _sql_text(grid_version),
                )
            )
            + ")"
        )
    return rows


def render_migration(snapshot: dict[str, object]) -> str:
    rows = ",\n".join(_station_rows(snapshot))
    return f"""-- Backfills Escalador centrally and supplies elevations for old clients.
-- Elevations are derived from the bundled IGN/CNIG terrain grid (CC BY 4.0).
create table if not exists public.bicimad_station_elevations (
  canonical_code text primary key,
  station_id text not null unique,
  station_name text not null,
  latitude double precision not null,
  longitude double precision not null,
  elevation_meters double precision not null,
  terrain_grid_version text not null,
  updated_at timestamptz not null default now(),
  constraint bicimad_station_elevations_code_format
    check (canonical_code ~ '^[0-9]+[a-z]?$'),
  constraint bicimad_station_elevations_plausible_height
    check (elevation_meters between 300 and 1200)
);

alter table public.bicimad_station_elevations enable row level security;
revoke all on table public.bicimad_station_elevations
  from public, anon, authenticated;

insert into public.bicimad_station_elevations (
  canonical_code,
  station_id,
  station_name,
  latitude,
  longitude,
  elevation_meters,
  terrain_grid_version
) values
{rows}
on conflict (canonical_code) do update set
  station_id = excluded.station_id,
  station_name = excluded.station_name,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  elevation_meters = excluded.elevation_meters,
  terrain_grid_version = excluded.terrain_grid_version,
  updated_at = now();

create or replace function public.bicimad_station_elevation(
  p_station_id text,
  p_station_name text,
  p_latitude double precision,
  p_longitude double precision
)
returns double precision
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  resolved_elevation double precision;
begin
  select station.elevation_meters
    into resolved_elevation
  from public.bicimad_station_elevations station
  where station.canonical_code = public.bicimad_public_station_code(
    p_station_id,
    p_station_name
  );
  if found then
    return resolved_elevation;
  end if;

  select station.elevation_meters
    into resolved_elevation
  from public.bicimad_station_elevations station
  where station.station_id = nullif(btrim(p_station_id), '');
  if found then
    return resolved_elevation;
  end if;

  if p_latitude is null or p_longitude is null then
    return null;
  end if;
  select station.elevation_meters
    into resolved_elevation
  from public.bicimad_station_elevations station
  where abs(station.latitude - p_latitude) <= 0.00035
    and abs(station.longitude - p_longitude) <= 0.00035
  order by
    power(station.latitude - p_latitude, 2)
      + power(station.longitude - p_longitude, 2)
  limit 1;
  return resolved_elevation;
end;
$$;

revoke all on function public.bicimad_station_elevation(
  text, text, double precision, double precision
) from public, anon, authenticated;

create or replace function public.fill_trip_net_elevation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  origin_elevation double precision;
  destination_elevation double precision;
begin
  if new.net_elevation_meters is not null then
    return new;
  end if;

  origin_elevation := public.bicimad_station_elevation(
    new.origin_station_id,
    new.origin_station_name,
    new.origin_latitude,
    new.origin_longitude
  );
  destination_elevation := public.bicimad_station_elevation(
    new.destination_station_id,
    new.destination_station_name,
    new.destination_latitude,
    new.destination_longitude
  );

  if origin_elevation is not null and destination_elevation is not null then
    new.net_elevation_meters := destination_elevation - origin_elevation;
  end if;
  return new;
end;
$$;

revoke all on function public.fill_trip_net_elevation()
  from public, anon, authenticated;

drop trigger if exists trips_fill_net_elevation on public.trips;
create trigger trips_fill_net_elevation
before insert or update of
  origin_station_id,
  origin_station_name,
  destination_station_id,
  destination_station_name,
  origin_latitude,
  origin_longitude,
  destination_latitude,
  destination_longitude,
  net_elevation_meters
on public.trips
for each row
when (new.net_elevation_meters is null)
execute function public.fill_trip_net_elevation();

do $$
declare
  batch_count integer := 0;
  backfilled_count integer := 0;
  unresolved_count integer := 0;
  existing_profile record;
begin
  loop
    with resolved as materialized (
      select
        trip.id,
        public.bicimad_station_elevation(
          trip.origin_station_id,
          trip.origin_station_name,
          trip.origin_latitude,
          trip.origin_longitude
        ) as origin_elevation,
        public.bicimad_station_elevation(
          trip.destination_station_id,
          trip.destination_station_name,
          trip.destination_latitude,
          trip.destination_longitude
        ) as destination_elevation
      from public.trips trip
      where trip.net_elevation_meters is null
    ),
    calculable as (
      select *
      from resolved
      where origin_elevation is not null
        and destination_elevation is not null
      order by id
      limit 500
    )
    update public.trips trip
    set net_elevation_meters =
      calculable.destination_elevation - calculable.origin_elevation
    from calculable
    where trip.id = calculable.id;

    get diagnostics batch_count = row_count;
    backfilled_count := backfilled_count + batch_count;
    exit when batch_count = 0;
  end loop;

  select count(*)::integer
    into unresolved_count
  from public.trips trip
  where trip.net_elevation_meters is null;

  for existing_profile in
    select profile.user_id from public.profiles profile
  loop
    perform public.refresh_profile_achievements(existing_profile.user_id);
  end loop;

  raise notice 'Escalador elevation backfill: % updated, % unresolved',
    backfilled_count,
    unresolved_count;
end;
$$;
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    snapshot = json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_migration(snapshot), encoding="utf-8")
    print(f"Generated {output} with {len(snapshot['stations'])} stations")


if __name__ == "__main__":
    main()
