create or replace function public.get_community_route_ranking(
  p_origin_station_id text,
  p_destination_station_id text
)
returns table (
  user_id uuid,
  display_name text,
  username text,
  avatar_key text,
  duration_milliseconds bigint,
  direct_distance_meters double precision,
  started_at timestamptz,
  is_current_user boolean
)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  with recursive
  request_context as (
    select auth.uid() as current_user_id
  ),
  participants as (
    select context.current_user_id as user_id
    from request_context context
    where context.current_user_id is not null
    union
    select follow.following_id
    from public.follows follow
    cross join request_context context
    where follow.follower_id = context.current_user_id
      and follow.status = 'accepted'
  ),
  ordered_stages as (
    select
      trip.id,
      trip.user_id,
      trip.origin_station_id,
      trip.destination_station_id,
      trip.started_at,
      trip.started_at + trip.duration_seconds * interval '1 second' as ended_at,
      trip.origin_latitude,
      trip.origin_longitude,
      trip.destination_latitude,
      trip.destination_longitude,
      trip.direct_distance_meters,
      row_number() over (
        partition by trip.user_id
        order by trip.started_at, trip.id
      ) as stage_number
    from public.trips trip
    join participants participant on participant.user_id = trip.user_id
    where trip.provider = 'bicimad'
      and trip.duration_seconds > 0
      and trip.origin_station_id <> trip.destination_station_id
  ),
  journey_walk as (
    select
      stage.*,
      1::bigint as journey_number,
      stage.origin_station_id as journey_origin_station_id
    from ordered_stages stage
    where stage.stage_number = 1

    union all

    select
      next_stage.*,
      case when connection.is_continuation
        then previous.journey_number
        else previous.journey_number + 1
      end,
      case when connection.is_continuation
        then previous.journey_origin_station_id
        else next_stage.origin_station_id
      end
    from journey_walk previous
    join ordered_stages next_stage
      on next_stage.user_id = previous.user_id
      and next_stage.stage_number = previous.stage_number + 1
    cross join lateral (
      select (
        extract(epoch from next_stage.started_at - previous.ended_at)
          between 0 and 119
        and previous.destination_station_id = next_stage.origin_station_id
        and previous.journey_origin_station_id
          <> next_stage.destination_station_id
      ) as is_continuation
    ) connection
  ),
  grouped_stages as (
    select
      stage.*,
      row_number() over (
        partition by stage.user_id, stage.journey_number
        order by stage.stage_number
      ) as journey_stage_number
    from journey_walk stage
  ),
  route_candidates as (
    select
      first_stage.user_id,
      first_stage.started_at,
      round(
        extract(epoch from last_stage.ended_at - first_stage.started_at)
          * 1000
      )::bigint as duration_milliseconds,
      case
        when first_stage.journey_stage_number
          = last_stage.journey_stage_number
          then first_stage.direct_distance_meters
        when first_stage.origin_latitude is not null
          and first_stage.origin_longitude is not null
          and last_stage.destination_latitude is not null
          and last_stage.destination_longitude is not null
          then 6371000.0 * 2 * asin(
            sqrt(
              least(
                1.0,
                power(
                  sin(
                    radians(
                      last_stage.destination_latitude
                        - first_stage.origin_latitude
                    ) / 2
                  ),
                  2
                )
                + cos(radians(first_stage.origin_latitude))
                  * cos(radians(last_stage.destination_latitude))
                  * power(
                    sin(
                      radians(
                        last_stage.destination_longitude
                          - first_stage.origin_longitude
                      ) / 2
                    ),
                    2
                  )
              )
            )
          )
        else null
      end as direct_distance_meters
    from grouped_stages first_stage
    join grouped_stages last_stage
      on last_stage.user_id = first_stage.user_id
      and last_stage.journey_number = first_stage.journey_number
      and last_stage.journey_stage_number
        >= first_stage.journey_stage_number
    where first_stage.origin_station_id = p_origin_station_id
      and last_stage.destination_station_id = p_destination_station_id
      and first_stage.origin_station_id <> last_stage.destination_station_id
  ),
  best_by_user as (
    select distinct on (candidate.user_id)
      candidate.user_id,
      candidate.started_at,
      candidate.duration_milliseconds,
      candidate.direct_distance_meters
    from route_candidates candidate
    where candidate.duration_milliseconds > 0
    order by
      candidate.user_id,
      candidate.duration_milliseconds,
      candidate.started_at desc
  )
  select
    best.user_id,
    profile.display_name,
    profile.username,
    profile.avatar_key,
    best.duration_milliseconds,
    best.direct_distance_meters,
    case when best.user_id = context.current_user_id
      then best.started_at
      else null
    end as started_at,
    best.user_id = context.current_user_id as is_current_user
  from best_by_user best
  join public.profiles profile on profile.user_id = best.user_id
  cross join request_context context
  order by best.duration_milliseconds;
$$;

revoke all on function public.get_community_route_ranking(text, text)
  from public;
grant execute on function public.get_community_route_ranking(text, text)
  to authenticated;
