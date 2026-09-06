-- BiciMAD emits these labels for rentals that do not represent a valid
-- station-to-station trip. Keep them out of every cloud-derived feature.
create or replace function public.is_discarded_bicimad_station_name(
  p_station_name text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select translate(
    lower(
      regexp_replace(
        btrim(coalesce(p_station_name, '')),
        '^[[:space:]]*[0-9]+[[:space:]]*-[[:space:]]*',
        ''
      )
    ),
    'áéíóúü',
    'aeiouu'
  ) in ('bici mal anclada', 'ubicacion no permitida');
$$;

create temporary table discarded_bicimad_trip_users (
  user_id uuid primary key
) on commit drop;

insert into discarded_bicimad_trip_users(user_id)
select distinct trip.user_id
from public.trips trip
where trip.provider = 'bicimad'
  and (
    public.is_discarded_bicimad_station_name(trip.origin_station_name)
    or public.is_discarded_bicimad_station_name(
      trip.destination_station_name
    )
  );

delete from public.trips trip
where trip.provider = 'bicimad'
  and (
    public.is_discarded_bicimad_station_name(trip.origin_station_name)
    or public.is_discarded_bicimad_station_name(
      trip.destination_station_name
    )
  );

create or replace function public.discard_invalid_bicimad_trip()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.provider = 'bicimad'
    and (
      public.is_discarded_bicimad_station_name(new.origin_station_name)
      or public.is_discarded_bicimad_station_name(
        new.destination_station_name
      )
    ) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists discard_invalid_bicimad_trip on public.trips;
create trigger discard_invalid_bicimad_trip
before insert or update on public.trips
for each row execute function public.discard_invalid_bicimad_trip();

-- Rebuild all affected aggregates after removing the invalid source rows.
delete from public.user_achievements achievement
using discarded_bicimad_trip_users affected
where achievement.user_id = affected.user_id;

do $$
declare
  affected record;
begin
  for affected in select user_id from discarded_bicimad_trip_users loop
    perform public.refresh_profile_stats(affected.user_id);
    perform public.refresh_profile_achievements(affected.user_id);
  end loop;
end;
$$;

revoke all on function public.is_discarded_bicimad_station_name(text)
  from public;
revoke all on function public.discard_invalid_bicimad_trip() from public;
