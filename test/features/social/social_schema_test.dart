import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String tripDetailsMigration;
  late String profileCountsMigration;
  late String accountDeletionMigration;
  late String canonicalStatsMigration;

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
}
