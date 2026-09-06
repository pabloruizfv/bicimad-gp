alter function public.refresh_profile_achievement_levels(uuid)
  rename to refresh_profile_previous_achievement_levels;

create or replace function public.refresh_profile_long_trip_achievement(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  long_trip_progress integer := 0;
begin
  -- The preceding achievement refresh builds canonical journeys in this
  -- transaction, including endpoint distance for journeys with pit stops.
  insert into public.user_achievements (
    user_id,
    category_id,
    level_id,
    threshold,
    progress,
    unlocked_at,
    updated_at
  )
  with running_progress as (
    select
      journey.ended_at,
      sum(
        case
          when journey.direct_distance_meters > 5000.0 then 1
          else 0
        end
      ) over (order by journey.journey_index) as progress_value
    from pg_temp.achievement_journeys journey
  )
  select
    p_user_id,
    'long_trips_5_km',
    level.level_id,
    level.threshold,
    level.threshold,
    min(progress.ended_at),
    now()
  from (values
    ('graphite', 1),
    ('bronze', 15),
    ('silver', 50),
    ('gold', 200)
  ) as level(level_id, threshold)
  join running_progress progress
    on progress.progress_value >= level.threshold
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

  select count(*)::integer
    into long_trip_progress
  from pg_temp.achievement_journeys journey
  where journey.direct_distance_meters > 5000.0;

  update public.user_achievements achievement
  set progress = greatest(long_trip_progress, achievement.threshold),
      updated_at = now()
  where achievement.user_id = p_user_id
    and achievement.category_id = 'long_trips_5_km';
end;
$$;

create or replace function public.refresh_profile_achievement_levels(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.refresh_profile_previous_achievement_levels(p_user_id);
  perform public.refresh_profile_long_trip_achievement(p_user_id);
end;
$$;

revoke all on function public.refresh_profile_previous_achievement_levels(uuid)
  from public;
revoke all on function public.refresh_profile_long_trip_achievement(uuid)
  from public;
revoke all on function public.refresh_profile_achievement_levels(uuid)
  from public;

do $$
declare
  existing_profile record;
begin
  for existing_profile in select profile.user_id from public.profiles profile loop
    perform public.refresh_profile_achievements(existing_profile.user_id);
  end loop;
end;
$$;
