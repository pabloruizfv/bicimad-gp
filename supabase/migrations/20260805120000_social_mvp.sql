create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null,
  avatar_key text not null,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,20}$'),
  constraint profiles_display_name_length check (char_length(btrim(display_name)) between 1 and 40),
  constraint profiles_avatar_key check (avatar_key in ('1.png', '2.png', '3.png', '4.png'))
);

create table public.profile_private (
  user_id uuid primary key references auth.users(id) on delete cascade,
  mpass_user_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.follows (
  follower_id uuid not null references public.profiles(user_id) on delete cascade,
  following_id uuid not null references public.profiles(user_id) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_not_self check (follower_id <> following_id)
);

create table public.trips (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  source_trip_id text not null,
  origin_station_id text not null,
  origin_station_name text not null,
  destination_station_id text not null,
  destination_station_name text not null,
  started_at timestamptz not null,
  duration_seconds integer not null check (duration_seconds > 0),
  origin_latitude double precision,
  origin_longitude double precision,
  destination_latitude double precision,
  destination_longitude double precision,
  direct_distance_meters double precision check (
    direct_distance_meters is null or direct_distance_meters >= 0
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider, source_trip_id)
);

create table public.profile_stats (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  total_trips bigint not null default 0,
  distinct_trip_days bigint not null default 0,
  total_duration_seconds bigint not null default 0,
  total_distance_meters double precision not null default 0,
  equivalent_average_speed_kmh double precision,
  trips_with_distance bigint not null default 0,
  updated_at timestamptz not null default now()
);

create index profiles_display_name_search_idx on public.profiles (lower(display_name));
create index follows_following_status_idx on public.follows (following_id, status);
create index follows_follower_status_idx on public.follows (follower_id, status);
create index trips_user_started_idx on public.trips (user_id, started_at desc);

alter table public.profiles enable row level security;
alter table public.profile_private enable row level security;
alter table public.follows enable row level security;
alter table public.trips enable row level security;
alter table public.profile_stats enable row level security;

create policy profiles_authenticated_read
on public.profiles for select to authenticated
using (true);

create policy profiles_insert_own
on public.profiles for insert to authenticated
with check (user_id = auth.uid());

create policy profiles_update_own
on public.profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy profile_private_own_read
on public.profile_private for select to authenticated
using (user_id = auth.uid());

create policy profile_private_own_insert
on public.profile_private for insert to authenticated
with check (user_id = auth.uid());

create policy profile_private_own_update
on public.profile_private for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy follows_participant_read
on public.follows for select to authenticated
using (follower_id = auth.uid() or following_id = auth.uid());

create policy trips_owner_read
on public.trips for select to authenticated
using (user_id = auth.uid());

create policy profile_stats_allowed_read
on public.profile_stats for select to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.user_id = profile_stats.user_id and p.is_public
  )
  or exists (
    select 1 from public.follows f
    where f.follower_id = auth.uid()
      and f.following_id = profile_stats.user_id
      and f.status = 'accepted'
  )
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger profile_private_set_updated_at
before update on public.profile_private
for each row execute function public.set_updated_at();

create trigger follows_set_updated_at
before update on public.follows
for each row execute function public.set_updated_at();

create trigger trips_set_updated_at
before update on public.trips
for each row execute function public.set_updated_at();

create or replace function public.prevent_username_change()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.username is distinct from old.username then
    raise exception 'username_is_immutable';
  end if;
  return new;
end;
$$;

create trigger profiles_username_immutable
before update on public.profiles
for each row execute function public.prevent_username_change();

create or replace function public.refresh_profile_stats(p_user_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.profile_stats (
    user_id,
    total_trips,
    distinct_trip_days,
    total_duration_seconds,
    total_distance_meters,
    equivalent_average_speed_kmh,
    trips_with_distance,
    updated_at
  )
  select
    p_user_id,
    count(*),
    count(distinct (t.started_at at time zone 'Europe/Madrid')::date),
    coalesce(sum(t.duration_seconds), 0),
    coalesce(sum(t.direct_distance_meters), 0),
    case
      when coalesce(sum(t.duration_seconds), 0) > 0
        then coalesce(sum(t.direct_distance_meters), 0)
          / sum(t.duration_seconds) * 3.6
      else null
    end,
    count(t.direct_distance_meters),
    now()
  from public.trips t
  where t.user_id = p_user_id
  on conflict (user_id) do update set
    total_trips = excluded.total_trips,
    distinct_trip_days = excluded.distinct_trip_days,
    total_duration_seconds = excluded.total_duration_seconds,
    total_distance_meters = excluded.total_distance_meters,
    equivalent_average_speed_kmh = excluded.equivalent_average_speed_kmh,
    trips_with_distance = excluded.trips_with_distance,
    updated_at = excluded.updated_at;
$$;

create or replace function public.create_own_profile(
  p_username text,
  p_display_name text,
  p_avatar_key text,
  p_is_public boolean,
  p_mpass_user_id text default null
)
returns setof public.profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;
  insert into public.profiles (
    user_id, username, display_name, avatar_key, is_public
  ) values (
    v_user_id, lower(btrim(p_username)), btrim(p_display_name), p_avatar_key, p_is_public
  );
  insert into public.profile_private (user_id, mpass_user_id)
  values (v_user_id, nullif(btrim(p_mpass_user_id), ''))
  on conflict (user_id) do update set
    mpass_user_id = coalesce(excluded.mpass_user_id, profile_private.mpass_user_id);
  insert into public.profile_stats (user_id) values (v_user_id)
  on conflict (user_id) do nothing;
  return query select p.* from public.profiles p where p.user_id = v_user_id;
end;
$$;

create or replace function public.update_own_profile(
  p_display_name text,
  p_avatar_key text,
  p_is_public boolean
)
returns setof public.profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;
  update public.profiles p set
    display_name = btrim(p_display_name),
    avatar_key = p_avatar_key,
    is_public = p_is_public
  where p.user_id = v_user_id;
  return query select p.* from public.profiles p where p.user_id = v_user_id;
end;
$$;

create or replace function public.request_follow(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_target_public boolean;
begin
  if v_user_id is null or v_user_id = p_user_id then
    raise exception 'invalid_follow_target';
  end if;
  select p.is_public into v_target_public from public.profiles p
  where p.user_id = p_user_id;
  if not found then
    raise exception 'profile_not_found';
  end if;
  insert into public.follows (follower_id, following_id, status)
  values (
    v_user_id,
    p_user_id,
    case when v_target_public then 'accepted' else 'pending' end
  )
  on conflict (follower_id, following_id) do update set
    status = case when v_target_public then 'accepted' else follows.status end;
end;
$$;

create or replace function public.accept_follow_request(p_user_id uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  update public.follows set status = 'accepted'
  where follower_id = p_user_id and following_id = auth.uid() and status = 'pending';
$$;

create or replace function public.reject_follow_request(p_user_id uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.follows
  where follower_id = p_user_id and following_id = auth.uid() and status = 'pending';
$$;

create or replace function public.cancel_follow_request(p_user_id uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.follows
  where follower_id = auth.uid() and following_id = p_user_id and status = 'pending';
$$;

create or replace function public.unfollow_profile(p_user_id uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.follows
  where follower_id = auth.uid() and following_id = p_user_id;
$$;

create or replace function public.remove_follower(p_user_id uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.follows
  where follower_id = p_user_id and following_id = auth.uid();
$$;

create or replace function public.search_social_profiles(p_query text)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_key text,
  is_public boolean,
  outgoing_status text,
  follows_current_user boolean
)
language sql
security definer
set search_path = public, pg_temp
as $$
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
    )
  from public.profiles p
  left join public.follows outgoing
    on outgoing.follower_id = auth.uid() and outgoing.following_id = p.user_id
  where p.user_id <> auth.uid()
    and (
      p.username like lower(btrim(p_query)) || '%'
      or lower(p.display_name) like '%' || lower(btrim(p_query)) || '%'
    )
  order by
    case when p.username = lower(btrim(p_query)) then 0 else 1 end,
    p.username
  limit 50;
$$;

create or replace function public.list_social_connections(p_kind text)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_key text,
  is_public boolean,
  outgoing_status text,
  follows_current_user boolean,
  status text,
  direction text,
  created_at timestamptz
)
language sql
security definer
set search_path = public, pg_temp
as $$
  select
    p.user_id,
    p.username,
    p.display_name,
    p.avatar_key,
    p.is_public,
    outgoing.status,
    exists (
      select 1 from public.follows reverse_follow
      where reverse_follow.follower_id = p.user_id
        and reverse_follow.following_id = auth.uid()
        and reverse_follow.status = 'accepted'
    ),
    f.status,
    case when f.follower_id = auth.uid() then 'outgoing' else 'incoming' end,
    f.created_at
  from public.follows f
  join public.profiles p on p.user_id = case
    when f.follower_id = auth.uid() then f.following_id else f.follower_id end
  left join public.follows outgoing
    on outgoing.follower_id = auth.uid() and outgoing.following_id = p.user_id
  where
    (p_kind = 'followers' and f.following_id = auth.uid() and f.status = 'accepted')
    or (p_kind = 'following' and f.follower_id = auth.uid() and f.status = 'accepted')
    or (p_kind = 'received_requests' and f.following_id = auth.uid() and f.status = 'pending')
    or (p_kind = 'sent_requests' and f.follower_id = auth.uid() and f.status = 'pending')
  order by f.created_at desc;
$$;

create or replace function public.get_social_profile(p_user_id uuid)
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
  total_duration_seconds bigint,
  total_distance_meters double precision,
  equivalent_average_speed_kmh double precision,
  trips_with_distance bigint
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
    case when p.can_view then coalesce(s.total_duration_seconds, 0) else null end,
    case when p.can_view then coalesce(s.total_distance_meters, 0) else null end,
    case when p.can_view then s.equivalent_average_speed_kmh else null end,
    case when p.can_view then coalesce(s.trips_with_distance, 0) else null end
  from visible_profile p
  left join public.profile_stats s on s.user_id = p.user_id
  left join public.follows outgoing
    on outgoing.follower_id = auth.uid() and outgoing.following_id = p.user_id;
$$;

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
    direct_distance_meters
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
    r.direct_distance_meters
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
    direct_distance_meters double precision
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
    direct_distance_meters = coalesce(excluded.direct_distance_meters, existing.direct_distance_meters);

  get diagnostics v_count = row_count;
  perform public.refresh_profile_stats(v_user_id);
  return v_count;
end;
$$;

revoke all on public.profile_private from anon, authenticated;
revoke all on public.trips from anon;
revoke insert, update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.trips from authenticated;
revoke insert, update, delete on public.follows from anon, authenticated;
revoke insert, update, delete on public.profile_stats from anon, authenticated;

grant select on public.profiles to authenticated;
grant select on public.follows to authenticated;
grant select on public.trips to authenticated;
grant select on public.profile_stats to authenticated;

revoke all on function public.create_own_profile(text, text, text, boolean, text) from public;
revoke all on function public.update_own_profile(text, text, boolean) from public;
revoke all on function public.request_follow(uuid) from public;
revoke all on function public.accept_follow_request(uuid) from public;
revoke all on function public.reject_follow_request(uuid) from public;
revoke all on function public.cancel_follow_request(uuid) from public;
revoke all on function public.unfollow_profile(uuid) from public;
revoke all on function public.remove_follower(uuid) from public;
revoke all on function public.search_social_profiles(text) from public;
revoke all on function public.list_social_connections(text) from public;
revoke all on function public.get_social_profile(uuid) from public;
revoke all on function public.upsert_own_trips(jsonb) from public;
revoke all on function public.refresh_profile_stats(uuid) from public;

grant execute on function public.create_own_profile(text, text, text, boolean, text) to authenticated;
grant execute on function public.update_own_profile(text, text, boolean) to authenticated;
grant execute on function public.request_follow(uuid) to authenticated;
grant execute on function public.accept_follow_request(uuid) to authenticated;
grant execute on function public.reject_follow_request(uuid) to authenticated;
grant execute on function public.cancel_follow_request(uuid) to authenticated;
grant execute on function public.unfollow_profile(uuid) to authenticated;
grant execute on function public.remove_follower(uuid) to authenticated;
grant execute on function public.search_social_profiles(text) to authenticated;
grant execute on function public.list_social_connections(text) to authenticated;
grant execute on function public.get_social_profile(uuid) to authenticated;
grant execute on function public.upsert_own_trips(jsonb) to authenticated;
