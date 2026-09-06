create or replace function public.refresh_profile_bike_achievement(
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
  current_ended_at timestamptz;
  current_origin_id text;
  current_destination_id text;
  journey_index_value bigint := 0;
  normalized_bike_id text;
  bike_usage_progress integer := 0;
begin
  create temporary table if not exists achievement_bike_journey_usage (
    journey_index bigint not null,
    bike_id text not null,
    used_at timestamptz not null,
    primary key (journey_index, bike_id)
  ) on commit drop;
  truncate table pg_temp.achievement_bike_journey_usage;

  for stage in
    select
      trip.id,
      trip.origin_station_id,
      trip.destination_station_id,
      trip.started_at,
      trip.started_at + trip.duration_seconds * interval '1 second' as ended_at,
      trip.bike_id
    from public.trips trip
    where trip.user_id = p_user_id
      and trip.duration_seconds > 0
      and trip.origin_station_id <> trip.destination_station_id
    order by trip.started_at, trip.id
  loop
    if not has_current then
      has_current := true;
      journey_index_value := journey_index_value + 1;
    elsif not (
      extract(epoch from stage.started_at - current_ended_at) between 0 and 119
      and current_destination_id = stage.origin_station_id
      and current_origin_id <> stage.destination_station_id
    ) then
      journey_index_value := journey_index_value + 1;
    end if;

    if not has_current or current_origin_id is null
      or not (
        extract(epoch from stage.started_at - current_ended_at) between 0 and 119
        and current_destination_id = stage.origin_station_id
        and current_origin_id <> stage.destination_station_id
      ) then
      current_origin_id := stage.origin_station_id;
    end if;
    current_destination_id := stage.destination_station_id;
    current_ended_at := stage.ended_at;

    normalized_bike_id := case
      when nullif(btrim(stage.bike_id), '') is null then null
      when btrim(stage.bike_id) ~ '^[0-9]+$' then
        coalesce(nullif(ltrim(btrim(stage.bike_id), '0'), ''), '0')
      else btrim(stage.bike_id)
    end;
    if normalized_bike_id is not null then
      insert into pg_temp.achievement_bike_journey_usage (
        journey_index,
        bike_id,
        used_at
      ) values (
        journey_index_value,
        normalized_bike_id,
        stage.ended_at
      )
      on conflict (journey_index, bike_id) do update set
        used_at = greatest(
          achievement_bike_journey_usage.used_at,
          excluded.used_at
        );
    end if;
    update pg_temp.achievement_bike_journey_usage usage
    set used_at = stage.ended_at
    where usage.journey_index = journey_index_value;
  end loop;

  insert into public.user_achievements (
    user_id,
    category_id,
    level_id,
    threshold,
    progress,
    unlocked_at,
    updated_at
  )
  with running_usage as (
    select
      usage.bike_id,
      usage.used_at,
      count(*) over (
        partition by usage.bike_id
        order by usage.journey_index
      ) as progress_value
    from pg_temp.achievement_bike_journey_usage usage
  )
  select
    p_user_id,
    'favorite_bike',
    level.level_id,
    level.threshold,
    level.threshold,
    min(usage.used_at),
    now()
  from (values
    ('graphite', 2),
    ('bronze', 3),
    ('silver', 4),
    ('gold', 5)
  ) as level(level_id, threshold)
  join running_usage usage on usage.progress_value >= level.threshold
  group by level.level_id, level.threshold
  on conflict (user_id, category_id, level_id) do update set
    threshold = excluded.threshold,
    progress = greatest(
      public.user_achievements.progress,
      excluded.progress
    ),
    unlocked_at = least(
      public.user_achievements.unlocked_at,
      excluded.unlocked_at
    ),
    updated_at = now();

  select coalesce(max(per_bike.usage_count), 0)::integer
    into bike_usage_progress
  from (
    select count(*) as usage_count
    from pg_temp.achievement_bike_journey_usage usage
    group by usage.bike_id
  ) per_bike;

  update public.user_achievements achievement
  set progress = greatest(bike_usage_progress, achievement.threshold),
      updated_at = now()
  where achievement.user_id = p_user_id
    and achievement.category_id = 'favorite_bike';
end;
$$;

revoke all on function public.refresh_profile_bike_achievement(uuid)
  from public;

delete from public.user_achievements
where category_id = 'favorite_bike';

do $$
declare
  existing_profile record;
begin
  for existing_profile in select profile.user_id from public.profiles profile loop
    perform public.refresh_profile_achievements(existing_profile.user_id);
  end loop;
end;
$$;
