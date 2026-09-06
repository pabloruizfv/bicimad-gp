create or replace function public.bicimad_station_display_name(
  p_station_id text,
  p_station_name text
)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  with station_values as (
    select
      public.bicimad_public_station_code(
        p_station_id,
        p_station_name
      ) as public_code,
      coalesce(
        nullif(btrim(regexp_replace(
          coalesce(p_station_name, ''),
          '^[[:space:]]*0*[0-9]+[[:space:]]*[[:alpha:]]?[[:space:]]*-[[:space:]]*',
          ''
        )), ''),
        nullif(btrim(p_station_name), '')
      ) as station_name
  )
  select case
    when public_code is not null and station_name is not null
      then public_code || ' - ' || station_name
    when station_name is not null then station_name
    when public_code is not null then public_code
    else nullif(btrim(p_station_id), '')
  end
  from station_values;
$$;

revoke all on function public.bicimad_station_display_name(text, text)
from public;

do $$
declare
  existing_profile record;
begin
  for existing_profile in select p.user_id from public.profiles p loop
    perform public.refresh_profile_stats(existing_profile.user_id);
  end loop;
end;
$$;
