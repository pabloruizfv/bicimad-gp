alter table public.user_achievements
  add column progress integer not null default 0
  check (progress >= 0);

alter function public.refresh_profile_achievements(uuid)
  rename to refresh_profile_achievement_levels;

create or replace function public.refresh_profile_achievement_progress(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  stage record;
  has_current boolean := false;
  current_started_at timestamptz;
  current_ended_at timestamptz;
  current_origin_id text;
  current_origin_name text;
  current_destination_id text;
  current_destination_name text;
  current_origin_lat double precision;
  current_origin_lon double precision;
  current_destination_lat double precision;
  current_destination_lon double precision;
  current_single_distance double precision;
  current_stage_count integer := 0;
  journey_duration_seconds double precision;
  journey_distance double precision;
  origin_key text;
  destination_key text;
  pit_stop_progress integer := 0;
  fast_trip_progress integer := 0;
  favorite_station_progress integer := 0;
begin
  create temporary table if not exists achievement_progress_station_usage (
    station_key text primary key,
    usage_count integer not null
  ) on commit drop;
  truncate table pg_temp.achievement_progress_station_usage;

  for stage in
    select
      trip.id,
      trip.origin_station_id,
      trip.origin_station_name,
      trip.destination_station_id,
      trip.destination_station_name,
      trip.started_at,
      trip.started_at + trip.duration_seconds * interval '1 second' as ended_at,
      trip.origin_latitude,
      trip.origin_longitude,
      trip.destination_latitude,
      trip.destination_longitude,
      trip.direct_distance_meters
    from public.trips trip
    where trip.user_id = p_user_id
      and trip.duration_seconds > 0
      and trip.origin_station_id <> trip.destination_station_id
    order by trip.started_at, trip.id
  loop
    if not has_current then
      has_current := true;
      current_started_at := stage.started_at;
      current_ended_at := stage.ended_at;
      current_origin_id := stage.origin_station_id;
      current_origin_name := stage.origin_station_name;
      current_destination_id := stage.destination_station_id;
      current_destination_name := stage.destination_station_name;
      current_origin_lat := stage.origin_latitude;
      current_origin_lon := stage.origin_longitude;
      current_destination_lat := stage.destination_latitude;
      current_destination_lon := stage.destination_longitude;
      current_single_distance := stage.direct_distance_meters;
      current_stage_count := 1;
    elsif extract(epoch from stage.started_at - current_ended_at) between 0 and 119
      and current_destination_id = stage.origin_station_id
      and current_origin_id <> stage.destination_station_id then
      current_ended_at := stage.ended_at;
      current_destination_id := stage.destination_station_id;
      current_destination_name := stage.destination_station_name;
      current_destination_lat := stage.destination_latitude;
      current_destination_lon := stage.destination_longitude;
      current_stage_count := current_stage_count + 1;
    else
      pit_stop_progress := pit_stop_progress
        + greatest(current_stage_count - 1, 0);
      journey_duration_seconds := extract(
        epoch from current_ended_at - current_started_at
      );
      journey_distance := case
        when current_stage_count = 1 then current_single_distance
        when current_origin_lat is not null
          and current_origin_lon is not null
          and current_destination_lat is not null
          and current_destination_lon is not null then
          2 * 6371000 * asin(sqrt(least(1.0,
            power(sin(radians(current_destination_lat - current_origin_lat) / 2), 2)
            + cos(radians(current_origin_lat))
              * cos(radians(current_destination_lat))
              * power(sin(radians(current_destination_lon - current_origin_lon) / 2), 2)
          )))
        else null
      end;
      if journey_distance is not null
        and journey_duration_seconds > 0
        and journey_distance / journey_duration_seconds * 3.6 > 14.000000001 then
        fast_trip_progress := fast_trip_progress + 1;
      end if;

      origin_key := coalesce(
        nullif(public.bicimad_public_station_code(
          current_origin_id,
          current_origin_name
        ), ''),
        'name:' || nullif(lower(regexp_replace(
          public.bicimad_station_display_name(
            current_origin_id,
            current_origin_name
          ),
          '[^[:alnum:]]+',
          '',
          'g'
        )), ''),
        'id:' || nullif(btrim(current_origin_id), '')
      );
      destination_key := coalesce(
        nullif(public.bicimad_public_station_code(
          current_destination_id,
          current_destination_name
        ), ''),
        'name:' || nullif(lower(regexp_replace(
          public.bicimad_station_display_name(
            current_destination_id,
            current_destination_name
          ),
          '[^[:alnum:]]+',
          '',
          'g'
        )), ''),
        'id:' || nullif(btrim(current_destination_id), '')
      );
      if origin_key is not null then
        insert into pg_temp.achievement_progress_station_usage (
          station_key,
          usage_count
        ) values (origin_key, 1)
        on conflict (station_key) do update set
          usage_count = achievement_progress_station_usage.usage_count + 1;
      end if;
      if destination_key is not null then
        insert into pg_temp.achievement_progress_station_usage (
          station_key,
          usage_count
        ) values (destination_key, 1)
        on conflict (station_key) do update set
          usage_count = achievement_progress_station_usage.usage_count + 1;
      end if;

      current_started_at := stage.started_at;
      current_ended_at := stage.ended_at;
      current_origin_id := stage.origin_station_id;
      current_origin_name := stage.origin_station_name;
      current_destination_id := stage.destination_station_id;
      current_destination_name := stage.destination_station_name;
      current_origin_lat := stage.origin_latitude;
      current_origin_lon := stage.origin_longitude;
      current_destination_lat := stage.destination_latitude;
      current_destination_lon := stage.destination_longitude;
      current_single_distance := stage.direct_distance_meters;
      current_stage_count := 1;
    end if;
  end loop;

  if has_current then
    pit_stop_progress := pit_stop_progress
      + greatest(current_stage_count - 1, 0);
    journey_duration_seconds := extract(
      epoch from current_ended_at - current_started_at
    );
    journey_distance := case
      when current_stage_count = 1 then current_single_distance
      when current_origin_lat is not null
        and current_origin_lon is not null
        and current_destination_lat is not null
        and current_destination_lon is not null then
        2 * 6371000 * asin(sqrt(least(1.0,
          power(sin(radians(current_destination_lat - current_origin_lat) / 2), 2)
          + cos(radians(current_origin_lat))
            * cos(radians(current_destination_lat))
            * power(sin(radians(current_destination_lon - current_origin_lon) / 2), 2)
        )))
      else null
    end;
    if journey_distance is not null
      and journey_duration_seconds > 0
      and journey_distance / journey_duration_seconds * 3.6 > 14.000000001 then
      fast_trip_progress := fast_trip_progress + 1;
    end if;

    origin_key := coalesce(
      nullif(public.bicimad_public_station_code(
        current_origin_id,
        current_origin_name
      ), ''),
      'name:' || nullif(lower(regexp_replace(
        public.bicimad_station_display_name(
          current_origin_id,
          current_origin_name
        ),
        '[^[:alnum:]]+',
        '',
        'g'
      )), ''),
      'id:' || nullif(btrim(current_origin_id), '')
    );
    destination_key := coalesce(
      nullif(public.bicimad_public_station_code(
        current_destination_id,
        current_destination_name
      ), ''),
      'name:' || nullif(lower(regexp_replace(
        public.bicimad_station_display_name(
          current_destination_id,
          current_destination_name
        ),
        '[^[:alnum:]]+',
        '',
        'g'
      )), ''),
      'id:' || nullif(btrim(current_destination_id), '')
    );
    if origin_key is not null then
      insert into pg_temp.achievement_progress_station_usage (
        station_key,
        usage_count
      ) values (origin_key, 1)
      on conflict (station_key) do update set
        usage_count = achievement_progress_station_usage.usage_count + 1;
    end if;
    if destination_key is not null then
      insert into pg_temp.achievement_progress_station_usage (
        station_key,
        usage_count
      ) values (destination_key, 1)
      on conflict (station_key) do update set
        usage_count = achievement_progress_station_usage.usage_count + 1;
    end if;
  end if;

  select coalesce(max(usage.usage_count), 0)
    into favorite_station_progress
  from pg_temp.achievement_progress_station_usage usage;

  update public.user_achievements achievement
  set progress = greatest(pit_stop_progress, achievement.threshold),
      updated_at = now()
  where achievement.user_id = p_user_id
    and achievement.category_id = 'pit_stops';

  update public.user_achievements achievement
  set progress = greatest(fast_trip_progress, achievement.threshold),
      updated_at = now()
  where achievement.user_id = p_user_id
    and achievement.category_id = 'fast_trips_14_kmh';

  update public.user_achievements achievement
  set progress = greatest(favorite_station_progress, achievement.threshold),
      updated_at = now()
  where achievement.user_id = p_user_id
    and achievement.category_id = 'favorite_station';
end;
$$;

create or replace function public.refresh_profile_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.refresh_profile_achievement_levels(p_user_id);
  perform public.refresh_profile_achievement_progress(p_user_id);
end;
$$;

create or replace function public.refresh_own_achievements()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  perform public.refresh_profile_achievements(current_user_id);
end;
$$;

revoke all on function public.refresh_profile_achievement_levels(uuid)
  from public;
revoke all on function public.refresh_profile_achievement_progress(uuid)
  from public;
revoke all on function public.refresh_profile_achievements(uuid) from public;
revoke all on function public.refresh_own_achievements() from public;
grant execute on function public.refresh_own_achievements() to authenticated;

do $$
declare
  existing_profile record;
begin
  for existing_profile in select profile.user_id from public.profiles profile loop
    perform public.refresh_profile_achievements(existing_profile.user_id);
  end loop;
end;
$$;
