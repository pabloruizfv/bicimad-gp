-- PUBLIC revocations do not remove grants made directly to API roles.
-- Scope this change to the application's objects; do not alter other schemas,
-- service_role, RLS policies, function bodies or previously applied migrations.
revoke all on table
  public.profiles, public.profile_private, public.follows, public.trips,
  public.profile_stats, public.user_achievements
from public, anon, authenticated;

grant select on table
  public.profiles, public.follows, public.trips, public.profile_stats,
  public.user_achievements
to authenticated;

revoke all on sequence public.trips_id_seq from public, anon, authenticated;

-- Internal helpers, including renamed achievement implementations, are only
-- called by the owning functions/triggers. They must not be callable via RPC.
do $$
declare
  signature text;
begin
  foreach signature in array array[
    'public.set_updated_at()',
    'public.prevent_username_change()',
    'public.refresh_profile_stats(uuid)',
    'public.bicimad_public_station_code(text,text)',
    'public.bicimad_station_display_name(text,text)',
    'public.refresh_profile_base_achievements(uuid)',
    'public.refresh_profile_station_achievement(uuid)',
    'public.refresh_profile_achievement_progress(uuid)',
    'public.refresh_profile_previous_achievement_levels(uuid)',
    'public.refresh_profile_long_trip_achievement(uuid)',
    'public.refresh_profile_levels_before_favorite_bike(uuid)',
    'public.refresh_profile_bike_achievement(uuid)',
    'public.refresh_profile_achievement_levels(uuid)',
    'public.refresh_profile_achievements(uuid)',
    'public.get_best_route_times_for_users(uuid[])',
    'public.is_discarded_bicimad_station_name(text)',
    'public.discard_invalid_bicimad_trip()',
    'public.create_own_profile(text,text,text,boolean,text)',
    'public.update_own_profile(text,text,boolean)',
    'public.request_follow(uuid)',
    'public.accept_follow_request(uuid)',
    'public.reject_follow_request(uuid)',
    'public.cancel_follow_request(uuid)',
    'public.unfollow_profile(uuid)',
    'public.remove_follower(uuid)',
    'public.search_social_profiles(text)',
    'public.list_social_connections(text)',
    'public.get_social_profile(uuid)',
    'public.upsert_own_trips(jsonb)',
    'public.delete_own_account()',
    'public.refresh_own_achievements()',
    'public.get_achievement_ranking(text)',
    'public.get_community_route_ranking(text,text)',
    'public.get_head_to_head(uuid)'
  ] loop
    if to_regprocedure(signature) is not null then
      execute format(
        'revoke all on function %s from public, anon, authenticated',
        signature
      );
    end if;
  end loop;
end;
$$;

-- These are the existing client entry points. Their auth.uid() checks and
-- privacy filters remain unchanged; all direct table reads still require RLS.
grant execute on function
  public.create_own_profile(text, text, text, boolean, text),
  public.update_own_profile(text, text, boolean),
  public.request_follow(uuid),
  public.accept_follow_request(uuid),
  public.reject_follow_request(uuid),
  public.cancel_follow_request(uuid),
  public.unfollow_profile(uuid),
  public.remove_follower(uuid),
  public.search_social_profiles(text),
  public.list_social_connections(text),
  public.get_social_profile(uuid),
  public.upsert_own_trips(jsonb),
  public.delete_own_account(),
  public.refresh_own_achievements(),
  public.get_achievement_ranking(text),
  public.get_community_route_ranking(text, text),
  public.get_head_to_head(uuid)
to authenticated;
