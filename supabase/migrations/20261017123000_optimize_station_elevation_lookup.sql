-- Avoid the coordinate fallback scan when code or station id already resolves.
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
