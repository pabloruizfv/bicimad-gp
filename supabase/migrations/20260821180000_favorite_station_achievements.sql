alter function public.refresh_profile_achievements(uuid)
  rename to refresh_profile_base_achievements;

create or replace function public.refresh_profile_station_achievement(
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
  current_origin_name text;
  current_destination_id text;
  current_destination_name text;
  journey_index_value bigint := 0;
  origin_key text;
  destination_key text;
begin
  create temporary table if not exists achievement_station_endpoints (
    endpoint_index bigint primary key,
    station_key text not null,
    used_at timestamptz not null
  ) on commit drop;
  truncate table pg_temp.achievement_station_endpoints;

  for stage in
    select
      trip.id,
      trip.origin_station_id,
      trip.origin_station_name,
      trip.destination_station_id,
      trip.destination_station_name,
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
      current_ended_at := stage.ended_at;
      current_origin_id := stage.origin_station_id;
      current_origin_name := stage.origin_station_name;
      current_destination_id := stage.destination_station_id;
      current_destination_name := stage.destination_station_name;
    elsif extract(epoch from stage.started_at - current_ended_at) between 0 and 119
      and current_destination_id = stage.origin_station_id
      and current_origin_id <> stage.destination_station_id then
      current_ended_at := stage.ended_at;
      current_destination_id := stage.destination_station_id;
      current_destination_name := stage.destination_station_name;
    else
      journey_index_value := journey_index_value + 1;
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
        insert into pg_temp.achievement_station_endpoints (
          endpoint_index,
          station_key,
          used_at
        ) values (journey_index_value * 2 - 1, origin_key, current_ended_at);
      end if;
      if destination_key is not null then
        insert into pg_temp.achievement_station_endpoints (
          endpoint_index,
          station_key,
          used_at
        ) values (journey_index_value * 2, destination_key, current_ended_at);
      end if;

      current_ended_at := stage.ended_at;
      current_origin_id := stage.origin_station_id;
      current_origin_name := stage.origin_station_name;
      current_destination_id := stage.destination_station_id;
      current_destination_name := stage.destination_station_name;
    end if;
  end loop;

  if has_current then
    journey_index_value := journey_index_value + 1;
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
      insert into pg_temp.achievement_station_endpoints (
        endpoint_index,
        station_key,
        used_at
      ) values (journey_index_value * 2 - 1, origin_key, current_ended_at);
    end if;
    if destination_key is not null then
      insert into pg_temp.achievement_station_endpoints (
        endpoint_index,
        station_key,
        used_at
      ) values (journey_index_value * 2, destination_key, current_ended_at);
    end if;
  end if;

  insert into public.user_achievements (
    user_id,
    category_id,
    level_id,
    threshold,
    unlocked_at,
    updated_at
  )
  with running_usage as (
    select
      endpoint.station_key,
      endpoint.used_at,
      count(*) over (
        partition by endpoint.station_key
        order by endpoint.endpoint_index
      ) as progress_value
    from pg_temp.achievement_station_endpoints endpoint
  )
  select
    p_user_id,
    'favorite_station',
    level.level_id,
    level.threshold,
    min(usage.used_at),
    now()
  from (values
    ('graphite', 10),
    ('bronze', 50),
    ('silver', 200),
    ('gold', 500)
  ) as level(level_id, threshold)
  join running_usage usage on usage.progress_value >= level.threshold
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

create or replace function public.refresh_profile_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.refresh_profile_base_achievements(p_user_id);
  perform public.refresh_profile_station_achievement(p_user_id);
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

revoke all on function public.refresh_profile_base_achievements(uuid)
  from public;
revoke all on function public.refresh_profile_station_achievement(uuid)
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
