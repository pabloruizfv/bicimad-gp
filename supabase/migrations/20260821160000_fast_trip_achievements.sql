create or replace function public.refresh_profile_achievements(p_user_id uuid)
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
  current_destination_id text;
  current_origin_lat double precision;
  current_origin_lon double precision;
  current_destination_lat double precision;
  current_destination_lon double precision;
  current_single_distance double precision;
  current_stage_count integer := 0;
  journey_distance double precision;
  journey_index_value bigint := 0;
begin
  create temporary table if not exists achievement_journeys (
    journey_index bigint primary key,
    ended_at timestamptz not null,
    pit_stop_count integer not null,
    duration_seconds bigint not null,
    direct_distance_meters double precision
  ) on commit drop;
  truncate table pg_temp.achievement_journeys;

  for stage in
    select
      trip.id,
      trip.origin_station_id,
      trip.destination_station_id,
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
      current_destination_id := stage.destination_station_id;
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
      current_destination_lat := stage.destination_latitude;
      current_destination_lon := stage.destination_longitude;
      current_stage_count := current_stage_count + 1;
    else
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
      journey_index_value := journey_index_value + 1;
      insert into pg_temp.achievement_journeys (
        journey_index,
        ended_at,
        pit_stop_count,
        duration_seconds,
        direct_distance_meters
      ) values (
        journey_index_value,
        current_ended_at,
        greatest(current_stage_count - 1, 0),
        extract(epoch from current_ended_at - current_started_at)::bigint,
        journey_distance
      );

      current_started_at := stage.started_at;
      current_ended_at := stage.ended_at;
      current_origin_id := stage.origin_station_id;
      current_destination_id := stage.destination_station_id;
      current_origin_lat := stage.origin_latitude;
      current_origin_lon := stage.origin_longitude;
      current_destination_lat := stage.destination_latitude;
      current_destination_lon := stage.destination_longitude;
      current_single_distance := stage.direct_distance_meters;
      current_stage_count := 1;
    end if;
  end loop;

  if has_current then
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
    journey_index_value := journey_index_value + 1;
    insert into pg_temp.achievement_journeys (
      journey_index,
      ended_at,
      pit_stop_count,
      duration_seconds,
      direct_distance_meters
    ) values (
      journey_index_value,
      current_ended_at,
      greatest(current_stage_count - 1, 0),
      extract(epoch from current_ended_at - current_started_at)::bigint,
      journey_distance
    );
  end if;

  insert into public.user_achievements (
    user_id,
    category_id,
    level_id,
    threshold,
    unlocked_at,
    updated_at
  )
  with progress as (
    select
      journey.ended_at,
      sum(journey.pit_stop_count) over (
        order by journey.journey_index
      ) as progress_value
    from pg_temp.achievement_journeys journey
  )
  select
    p_user_id,
    'pit_stops',
    level.level_id,
    level.threshold,
    min(progress.ended_at),
    now()
  from (values
    ('graphite', 1),
    ('bronze', 10),
    ('silver', 50),
    ('gold', 100)
  ) as level(level_id, threshold)
  join progress on progress.progress_value >= level.threshold
  group by level.level_id, level.threshold
  on conflict (user_id, category_id, level_id) do update set
    threshold = excluded.threshold,
    unlocked_at = least(
      public.user_achievements.unlocked_at,
      excluded.unlocked_at
    ),
    updated_at = now();

  insert into public.user_achievements (
    user_id,
    category_id,
    level_id,
    threshold,
    unlocked_at,
    updated_at
  )
  with progress as (
    select
      journey.ended_at,
      sum(
        case
          when journey.direct_distance_meters is not null
            and journey.duration_seconds > 0
            and journey.direct_distance_meters
              / journey.duration_seconds * 3.6 > 14.000000001
          then 1
          else 0
        end
      ) over (order by journey.journey_index) as progress_value
    from pg_temp.achievement_journeys journey
  )
  select
    p_user_id,
    'fast_trips_14_kmh',
    level.level_id,
    level.threshold,
    min(progress.ended_at),
    now()
  from (values
    ('graphite', 1),
    ('bronze', 10),
    ('silver', 50),
    ('gold', 100)
  ) as level(level_id, threshold)
  join progress on progress.progress_value >= level.threshold
  group by level.level_id, level.threshold
  on conflict (user_id, category_id, level_id) do update set
    threshold = excluded.threshold,
    unlocked_at = least(
      public.user_achievements.unlocked_at,
      excluded.unlocked_at
    ),
    updated_at = now();
end;
$$;

revoke all on function public.refresh_profile_achievements(uuid) from public;

do $$
declare
  existing_profile record;
begin
  for existing_profile in select profile.user_id from public.profiles profile loop
    perform public.refresh_profile_achievements(existing_profile.user_id);
  end loop;
end;
$$;
