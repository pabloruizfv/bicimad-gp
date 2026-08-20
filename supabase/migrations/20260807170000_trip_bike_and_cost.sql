alter table public.trips
  add column bike_id text,
  add column trip_cost numeric;

create or replace function public.upsert_own_trips(p_trips jsonb)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;
  if jsonb_typeof(p_trips) <> 'array' then
    raise exception 'invalid_trip_payload';
  end if;

  insert into public.trips as existing (
    user_id,
    provider,
    source_trip_id,
    origin_station_id,
    origin_station_name,
    destination_station_id,
    destination_station_name,
    started_at,
    duration_seconds,
    origin_latitude,
    origin_longitude,
    destination_latitude,
    destination_longitude,
    direct_distance_meters,
    bike_id,
    trip_cost
  )
  select
    v_user_id,
    r.provider,
    r.source_trip_id,
    r.origin_station_id,
    r.origin_station_name,
    r.destination_station_id,
    r.destination_station_name,
    r.started_at,
    r.duration_seconds,
    r.origin_latitude,
    r.origin_longitude,
    r.destination_latitude,
    r.destination_longitude,
    r.direct_distance_meters,
    r.bike_id,
    r.trip_cost
  from jsonb_to_recordset(p_trips) as r(
    provider text,
    source_trip_id text,
    origin_station_id text,
    origin_station_name text,
    destination_station_id text,
    destination_station_name text,
    started_at timestamptz,
    duration_seconds integer,
    origin_latitude double precision,
    origin_longitude double precision,
    destination_latitude double precision,
    destination_longitude double precision,
    direct_distance_meters double precision,
    bike_id text,
    trip_cost numeric
  )
  where r.provider = 'bicimad'
    and nullif(r.source_trip_id, '') is not null
    and r.duration_seconds > 0
  on conflict (user_id, provider, source_trip_id) do update set
    origin_station_id = coalesce(excluded.origin_station_id, existing.origin_station_id),
    origin_station_name = coalesce(excluded.origin_station_name, existing.origin_station_name),
    destination_station_id = coalesce(excluded.destination_station_id, existing.destination_station_id),
    destination_station_name = coalesce(excluded.destination_station_name, existing.destination_station_name),
    started_at = coalesce(excluded.started_at, existing.started_at),
    duration_seconds = coalesce(excluded.duration_seconds, existing.duration_seconds),
    origin_latitude = coalesce(excluded.origin_latitude, existing.origin_latitude),
    origin_longitude = coalesce(excluded.origin_longitude, existing.origin_longitude),
    destination_latitude = coalesce(excluded.destination_latitude, existing.destination_latitude),
    destination_longitude = coalesce(excluded.destination_longitude, existing.destination_longitude),
    direct_distance_meters = coalesce(excluded.direct_distance_meters, existing.direct_distance_meters),
    bike_id = coalesce(excluded.bike_id, existing.bike_id),
    trip_cost = coalesce(excluded.trip_cost, existing.trip_cost);

  get diagnostics v_count = row_count;
  perform public.refresh_profile_stats(v_user_id);
  return v_count;
end;
$$;

revoke all on function public.upsert_own_trips(jsonb) from public;
grant execute on function public.upsert_own_trips(jsonb) to authenticated;
