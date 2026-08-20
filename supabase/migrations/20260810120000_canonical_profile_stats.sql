alter table public.profile_stats
  add column if not exists history_span_days bigint not null default 0
  check (history_span_days >= 0);

create or replace function public.refresh_profile_stats(p_user_id uuid)
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
  total_trips_value bigint := 0;
  distinct_days_value bigint := 0;
  history_span_days_value bigint := 0;
  total_duration_value bigint := 0;
  total_distance_value double precision := 0;
  trips_with_distance_value bigint := 0;
  first_journey_at timestamptz;
  last_journey_at timestamptz;
begin
  create temporary table if not exists canonical_profile_journeys (
    started_at timestamptz not null,
    duration_seconds bigint not null,
    direct_distance_meters double precision
  ) on commit drop;
  truncate table pg_temp.canonical_profile_journeys;

  for stage in
    select
      t.id,
      t.origin_station_id,
      t.destination_station_id,
      t.started_at,
      t.started_at + t.duration_seconds * interval '1 second' as ended_at,
      t.origin_latitude,
      t.origin_longitude,
      t.destination_latitude,
      t.destination_longitude,
      t.direct_distance_meters
    from public.trips t
    where t.user_id = p_user_id
      and t.duration_seconds > 0
      and t.origin_station_id <> t.destination_station_id
    order by t.started_at, t.id
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
      insert into pg_temp.canonical_profile_journeys (
        started_at,
        duration_seconds,
        direct_distance_meters
      ) values (
        current_started_at,
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
    insert into pg_temp.canonical_profile_journeys (
      started_at,
      duration_seconds,
      direct_distance_meters
    ) values (
      current_started_at,
      extract(epoch from current_ended_at - current_started_at)::bigint,
      journey_distance
    );
  end if;

  select
    count(*),
    count(distinct (j.started_at at time zone 'Europe/Madrid')::date),
    coalesce(sum(j.duration_seconds), 0),
    coalesce(sum(j.direct_distance_meters), 0),
    count(j.direct_distance_meters),
    min(j.started_at),
    max(j.started_at)
  into
    total_trips_value,
    distinct_days_value,
    total_duration_value,
    total_distance_value,
    trips_with_distance_value,
    first_journey_at,
    last_journey_at
  from pg_temp.canonical_profile_journeys j;

  history_span_days_value := case
    when first_journey_at is null or last_journey_at is null then 0
    else (
      (last_journey_at at time zone 'Europe/Madrid')::date
      - (first_journey_at at time zone 'Europe/Madrid')::date
      + 1
    )::bigint
  end;

  insert into public.profile_stats (
    user_id,
    total_trips,
    distinct_trip_days,
    history_span_days,
    total_duration_seconds,
    total_distance_meters,
    equivalent_average_speed_kmh,
    trips_with_distance,
    updated_at
  ) values (
    p_user_id,
    total_trips_value,
    distinct_days_value,
    history_span_days_value,
    total_duration_value,
    total_distance_value,
    case
      when total_duration_value > 0
        then total_distance_value / total_duration_value * 3.6
      else null
    end,
    trips_with_distance_value,
    now()
  )
  on conflict (user_id) do update set
    total_trips = excluded.total_trips,
    distinct_trip_days = excluded.distinct_trip_days,
    history_span_days = excluded.history_span_days,
    total_duration_seconds = excluded.total_duration_seconds,
    total_distance_meters = excluded.total_distance_meters,
    equivalent_average_speed_kmh = excluded.equivalent_average_speed_kmh,
    trips_with_distance = excluded.trips_with_distance,
    updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.refresh_profile_stats(uuid) from public;

do $$
declare
  existing_profile record;
begin
  for existing_profile in select p.user_id from public.profiles p loop
    perform public.refresh_profile_stats(existing_profile.user_id);
  end loop;
end;
$$;

drop function if exists public.get_social_profile(uuid);

create function public.get_social_profile(p_user_id uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_key text,
  is_public boolean,
  outgoing_status text,
  follows_current_user boolean,
  can_view_stats boolean,
  total_trips bigint,
  distinct_trip_days bigint,
  history_span_days bigint,
  total_duration_seconds bigint,
  total_distance_meters double precision,
  equivalent_average_speed_kmh double precision,
  trips_with_distance bigint,
  followers_count bigint,
  following_count bigint
)
language sql
security definer
set search_path = public, pg_temp
as $$
  with visible_profile as (
    select
      p.*,
      (
        p.user_id = auth.uid()
        or p.is_public
        or exists (
          select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.following_id = p.user_id
            and f.status = 'accepted'
        )
      ) as can_view
    from public.profiles p where p.user_id = p_user_id
  )
  select
    p.user_id,
    p.username,
    p.display_name,
    p.avatar_key,
    p.is_public,
    outgoing.status,
    exists (
      select 1 from public.follows incoming
      where incoming.follower_id = p.user_id
        and incoming.following_id = auth.uid()
        and incoming.status = 'accepted'
    ),
    p.can_view,
    case when p.can_view then coalesce(s.total_trips, 0) else null end,
    case when p.can_view then coalesce(s.distinct_trip_days, 0) else null end,
    case when p.can_view then coalesce(s.history_span_days, 0) else null end,
    case when p.can_view then coalesce(s.total_duration_seconds, 0) else null end,
    case when p.can_view then coalesce(s.total_distance_meters, 0) else null end,
    case when p.can_view then s.equivalent_average_speed_kmh else null end,
    case when p.can_view then coalesce(s.trips_with_distance, 0) else null end,
    (
      select count(*)
      from public.follows followers
      where followers.following_id = p.user_id
        and followers.status = 'accepted'
    ),
    (
      select count(*)
      from public.follows following
      where following.follower_id = p.user_id
        and following.status = 'accepted'
    )
  from visible_profile p
  left join public.profile_stats s on s.user_id = p.user_id
  left join public.follows outgoing
    on outgoing.follower_id = auth.uid() and outgoing.following_id = p.user_id;
$$;

revoke all on function public.get_social_profile(uuid) from public;
grant execute on function public.get_social_profile(uuid) to authenticated;
