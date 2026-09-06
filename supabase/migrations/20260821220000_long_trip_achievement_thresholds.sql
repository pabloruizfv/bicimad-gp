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
    ('bronze', 10),
    ('silver', 20),
    ('gold', 50)
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
  set threshold = case achievement.level_id
        when 'graphite' then 1
        when 'bronze' then 10
        when 'silver' then 20
        when 'gold' then 50
        else achievement.threshold
      end,
      progress = greatest(
        long_trip_progress,
        case achievement.level_id
          when 'graphite' then 1
          when 'bronze' then 10
          when 'silver' then 20
          when 'gold' then 50
          else achievement.threshold
        end
      ),
      updated_at = now()
  where achievement.user_id = p_user_id
    and achievement.category_id = 'long_trips_5_km';
end;
$$;

revoke all on function public.refresh_profile_long_trip_achievement(uuid)
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
