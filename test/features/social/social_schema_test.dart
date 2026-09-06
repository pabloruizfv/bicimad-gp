import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String tripDetailsMigration;
  late String profileCountsMigration;
  late String accountDeletionMigration;
  late String canonicalStatsMigration;
  late String mostUsedStationMigration;
  late String stationPublicCodeMigration;
  late String discardedStationTripsMigration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260805120000_social_mvp.sql',
    ).readAsStringSync();
    tripDetailsMigration = File(
      'supabase/migrations/20260807170000_trip_bike_and_cost.sql',
    ).readAsStringSync();
    profileCountsMigration = File(
      'supabase/migrations/20260807143000_social_profile_counts.sql',
    ).readAsStringSync();
    accountDeletionMigration = File(
      'supabase/migrations/20260807190000_delete_own_account.sql',
    ).readAsStringSync();
    canonicalStatsMigration = File(
      'supabase/migrations/20260810120000_canonical_profile_stats.sql',
    ).readAsStringSync();
    mostUsedStationMigration = File(
      'supabase/migrations/20260820120000_profile_most_used_station.sql',
    ).readAsStringSync();
    stationPublicCodeMigration = File(
      'supabase/migrations/20260820200000_profile_station_public_code.sql',
    ).readAsStringSync();
    discardedStationTripsMigration = File(
      'supabase/migrations/20260826120000_discard_invalid_station_trips.sql',
    ).readAsStringSync();
  });

  test(
    'bicicleta y precio se agregan en una migracion nueva y enriquecible',
    () {
      expect(tripDetailsMigration, contains('add column bike_id text'));
      expect(tripDetailsMigration, contains('add column trip_cost numeric'));
      expect(
        tripDetailsMigration,
        contains('bike_id = coalesce(excluded.bike_id, existing.bike_id)'),
      );
      expect(
        tripDetailsMigration,
        contains(
          'trip_cost = coalesce(excluded.trip_cost, existing.trip_cost)',
        ),
      );
      expect(tripDetailsMigration, isNot(contains('service_role')));
    },
  );

  test('activa RLS y deduplica viajes por usuario proveedor e id fuente', () {
    expect(migration, contains('enable row level security'));
    expect(migration, contains('unique (user_id, provider, source_trip_id)'));
  });

  test('los viajes ajenos no tienen politica de lectura', () {
    expect(migration, contains('using (user_id = auth.uid())'));
    expect(migration, contains('revoke all on public.trips'));
    expect(migration, isNot(contains('service_role')));
  });

  test(
    'username es inmutable y el correo no forma parte del modelo publico',
    () {
      expect(migration, contains('prevent_username_change'));
      expect(migration, isNot(contains('email text')));
    },
  );

  test('los contadores sociales solo incluyen relaciones aceptadas', () {
    expect(profileCountsMigration, contains('followers_count bigint'));
    expect(profileCountsMigration, contains('following_count bigint'));
    expect(profileCountsMigration, contains("followers.status = 'accepted'"));
    expect(profileCountsMigration, contains("following.status = 'accepted'"));
    expect(profileCountsMigration, isNot(contains('email')));
  });

  test('el borrado de cuenta solo puede actuar sobre auth.uid', () {
    expect(accountDeletionMigration, contains('auth.uid()'));
    expect(
      accountDeletionMigration,
      contains('delete from auth.users where id = requesting_user_id'),
    );
    expect(accountDeletionMigration, contains('security definer'));
    expect(
      accountDeletionMigration,
      contains('grant execute on function public.delete_own_account()'),
    );
    expect(accountDeletionMigration, isNot(contains('service_role')));
    expect(accountDeletionMigration, isNot(contains('p_user_id')));
  });

  test('el borrado de auth.users propaga todos los datos sociales', () {
    expect(migration, contains('references auth.users(id) on delete cascade'));
    expect(
      migration,
      contains(
        'follower_id uuid not null references public.profiles(user_id) on delete cascade',
      ),
    );
    expect(
      migration,
      contains(
        'following_id uuid not null references public.profiles(user_id) on delete cascade',
      ),
    );
    expect(
      migration,
      contains(
        'user_id uuid primary key references public.profiles(user_id) on delete cascade',
      ),
    );
  });

  test('estadisticas cloud replican journeys y periodo natural', () {
    expect(
      canonicalStatsMigration,
      contains('add column if not exists history_span_days'),
    );
    expect(
      canonicalStatsMigration,
      contains('t.origin_station_id <> t.destination_station_id'),
    );
    expect(
      canonicalStatsMigration,
      contains(
        'extract(epoch from stage.started_at - current_ended_at) between 0 and 119',
      ),
    );
    expect(
      canonicalStatsMigration,
      contains('current_destination_id = stage.origin_station_id'),
    );
    expect(
      canonicalStatsMigration,
      contains('current_origin_id <> stage.destination_station_id'),
    );
    expect(canonicalStatsMigration, contains("at time zone 'Europe/Madrid'"));
    expect(canonicalStatsMigration, contains('total_distance_value'));
    expect(
      canonicalStatsMigration,
      contains('perform public.refresh_profile_stats'),
    );
    expect(canonicalStatsMigration, isNot(contains('service_role')));
  });

  test('estación más usada cuenta extremos de journeys y respeta privacidad', () {
    expect(
      mostUsedStationMigration,
      contains('add column if not exists most_used_station_name text'),
    );
    expect(
      mostUsedStationMigration,
      contains('current_destination_id = stage.origin_station_id'),
    );
    expect(mostUsedStationMigration, contains('with endpoints as'));
    expect(mostUsedStationMigration, contains('union all'));
    expect(
      mostUsedStationMigration,
      contains('public.bicimad_public_station_code'),
    );
    expect(
      mostUsedStationMigration,
      contains(
        'case when p.can_view_stats then s.most_used_station_name else null end',
      ),
    );
    expect(
      mostUsedStationMigration,
      contains(
        'case when p.can_view then s.most_used_station_name else null end',
      ),
    );
    expect(
      mostUsedStationMigration,
      contains(
        'perform public.refresh_profile_stats(existing_profile.user_id)',
      ),
    );
    expect(mostUsedStationMigration, isNot(contains('service_role')));
  });

  test('estación social conserva el código público en el nombre mostrado', () {
    expect(
      stationPublicCodeMigration,
      contains("public_code || ' - ' || station_name"),
    );
    expect(
      stationPublicCodeMigration,
      contains('public.bicimad_public_station_code'),
    );
    expect(
      stationPublicCodeMigration,
      contains(
        'perform public.refresh_profile_stats(existing_profile.user_id)',
      ),
    );
    expect(stationPublicCodeMigration, isNot(contains('service_role')));
  });
  test('descarta en nube los viajes de ubicaciones invalidas', () {
    expect(
      discardedStationTripsMigration,
      contains('is_discarded_bicimad_station_name'),
    );
    expect(discardedStationTripsMigration, contains('bici mal anclada'));
    expect(discardedStationTripsMigration, contains('ubicacion no permitida'));
    expect(
      discardedStationTripsMigration,
      contains('before insert or update on public.trips'),
    );
    expect(
      discardedStationTripsMigration,
      contains('delete from public.trips'),
    );
    expect(
      discardedStationTripsMigration,
      contains('perform public.refresh_profile_stats'),
    );
    expect(discardedStationTripsMigration, isNot(contains('service_role')));
  });
}
