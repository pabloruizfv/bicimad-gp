create table public.user_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id text not null,
  level_id text not null,
  threshold integer not null check (threshold > 0),
  unlocked_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, category_id, level_id),
  constraint user_achievements_category_format
    check (category_id ~ '^[a-z][a-z0-9_]{1,39}$'),
  constraint user_achievements_level
    check (level_id in ('graphite', 'bronze', 'silver', 'gold'))
);

alter table public.user_achievements enable row level security;

create policy user_achievements_allowed_read
on public.user_achievements
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.profiles profile
    where profile.user_id = user_achievements.user_id
      and (
        profile.is_public
        or exists (
          select 1
          from public.follows allowed_follow
          where allowed_follow.follower_id = auth.uid()
            and allowed_follow.following_id = user_achievements.user_id
            and allowed_follow.status = 'accepted'
        )
      )
  )
);

create or replace function public.refresh_profile_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  stage record;
  has_current boolean := false;
  current_origin_id text;
  current_destination_id text;
  current_ended_at timestamptz;
  current_stage_count integer := 0;
  previous_pit_stop_count integer := 0;
  total_pit_stop_count integer := 0;
begin
  for stage in
    select
      trip.id,
      trip.origin_station_id,
      trip.destination_station_id,
      trip.started_at,
      trip.started_at + trip.duration_seconds * interval '1 second' as ended_at
    from public.trips trip
    where trip.user_id = p_user_id
      and trip.duration_seconds > 0
      and trip.origin_station_id <> trip.destination_station_id
    order by trip.started_at, trip.id
  loop
    if not has_current then
      has_current := true;
      current_origin_id := stage.origin_station_id;
      current_destination_id := stage.destination_station_id;
      current_ended_at := stage.ended_at;
      current_stage_count := 1;
    elsif extract(epoch from stage.started_at - current_ended_at) between 0 and 119
      and current_destination_id = stage.origin_station_id
      and current_origin_id <> stage.destination_station_id then
      current_destination_id := stage.destination_station_id;
      current_ended_at := stage.ended_at;
      current_stage_count := current_stage_count + 1;
    else
      previous_pit_stop_count := total_pit_stop_count;
      total_pit_stop_count := total_pit_stop_count
        + greatest(current_stage_count - 1, 0);

      insert into public.user_achievements (
        user_id,
        category_id,
        level_id,
        threshold,
        unlocked_at,
        updated_at
      )
      select
        p_user_id,
        'pit_stops',
        level.level_id,
        level.threshold,
        current_ended_at,
        now()
      from (values
        ('graphite', 1),
        ('bronze', 10),
        ('silver', 50),
        ('gold', 100)
      ) as level(level_id, threshold)
      where previous_pit_stop_count < level.threshold
        and total_pit_stop_count >= level.threshold
      on conflict (user_id, category_id, level_id) do update set
        threshold = excluded.threshold,
        unlocked_at = least(
          public.user_achievements.unlocked_at,
          excluded.unlocked_at
        ),
        updated_at = now();

      current_origin_id := stage.origin_station_id;
      current_destination_id := stage.destination_station_id;
      current_ended_at := stage.ended_at;
      current_stage_count := 1;
    end if;
  end loop;

  if has_current then
    previous_pit_stop_count := total_pit_stop_count;
    total_pit_stop_count := total_pit_stop_count
      + greatest(current_stage_count - 1, 0);

    insert into public.user_achievements (
      user_id,
      category_id,
      level_id,
      threshold,
      unlocked_at,
      updated_at
    )
    select
      p_user_id,
      'pit_stops',
      level.level_id,
      level.threshold,
      current_ended_at,
      now()
    from (values
      ('graphite', 1),
      ('bronze', 10),
      ('silver', 50),
      ('gold', 100)
    ) as level(level_id, threshold)
    where previous_pit_stop_count < level.threshold
      and total_pit_stop_count >= level.threshold
    on conflict (user_id, category_id, level_id) do update set
      threshold = excluded.threshold,
      unlocked_at = least(
        public.user_achievements.unlocked_at,
        excluded.unlocked_at
      ),
      updated_at = now();
  end if;
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

revoke all on table public.user_achievements from anon, authenticated;
grant select on table public.user_achievements to authenticated;

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
