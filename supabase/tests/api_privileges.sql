-- Run after all migrations, with an administrative SQL connection.
-- No private rows are read and no changes are committed.
begin;
do $$
declare
  signature text;
  api_role text;
begin
  foreach signature in array array[
    'public.get_best_route_times_for_users(uuid[])',
    'public.refresh_profile_stats(uuid)',
    'public.refresh_profile_achievements(uuid)',
    'public.refresh_profile_base_achievements(uuid)',
    'public.refresh_profile_previous_achievement_levels(uuid)',
    'public.refresh_profile_levels_before_favorite_bike(uuid)'
  ] loop
    foreach api_role in array array['anon', 'authenticated'] loop
      if has_function_privilege(api_role, signature, 'EXECUTE') then
        raise exception 'Unexpected internal RPC access: % / %', api_role, signature;
      end if;
    end loop;
  end loop;

  foreach signature in array array[
    'public.get_social_profile(uuid)',
    'public.get_community_route_ranking(text,text)',
    'public.get_head_to_head(uuid)',
    'public.upsert_own_trips(jsonb)',
    'public.delete_own_account()',
    'public.refresh_own_achievements()'
  ] loop
    if has_function_privilege('anon', signature, 'EXECUTE')
      or not has_function_privilege('authenticated', signature, 'EXECUTE') then
      raise exception 'Unexpected public RPC access: %', signature;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.trips', 'INSERT,UPDATE,DELETE,TRUNCATE')
    or has_table_privilege('anon', 'public.trips', 'SELECT')
    or not has_table_privilege('authenticated', 'public.trips', 'SELECT') then
    raise exception 'Unexpected trips table privileges';
  end if;
end;
$$;
rollback;
