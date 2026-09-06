create or replace function public.get_achievement_ranking(
  p_category_id text
)
returns table (
  rank_position bigint,
  user_id uuid,
  display_name text,
  avatar_key text,
  metric_value integer,
  total_users bigint,
  is_current_user boolean
)
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_category_id is null
    or p_category_id !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'invalid achievement category' using errcode = '22023';
  end if;

  return query
  with visible_profiles as (
    select
      profile.user_id,
      profile.display_name,
      profile.avatar_key
    from public.profiles profile
    where profile.user_id = current_user_id
      or profile.is_public
      or exists (
        select 1
        from public.follows allowed_follow
        where allowed_follow.follower_id = current_user_id
          and allowed_follow.following_id = profile.user_id
          and allowed_follow.status = 'accepted'
      )
  ),
  category_progress as (
    select
      achievement.user_id,
      max(achievement.progress)::integer as metric_value
    from public.user_achievements achievement
    where achievement.category_id = p_category_id
    group by achievement.user_id
  ),
  ranked as (
    select
      row_number() over (
        order by
          coalesce(progress.metric_value, 0) desc,
          lower(profile.display_name),
          profile.user_id
      ) as rank_position,
      profile.user_id,
      profile.display_name,
      profile.avatar_key,
      coalesce(progress.metric_value, 0)::integer as metric_value,
      count(*) over () as total_users
    from visible_profiles profile
    left join category_progress progress
      on progress.user_id = profile.user_id
  )
  select
    ranked.rank_position,
    ranked.user_id,
    ranked.display_name,
    ranked.avatar_key,
    ranked.metric_value,
    ranked.total_users,
    ranked.user_id = current_user_id
  from ranked
  order by ranked.rank_position;
end;
$$;

revoke all on function public.get_achievement_ranking(text) from public;
grant execute on function public.get_achievement_ranking(text) to authenticated;
