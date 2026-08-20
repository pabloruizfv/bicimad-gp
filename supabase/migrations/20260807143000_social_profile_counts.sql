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
