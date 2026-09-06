import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('todas las variantes bronce comparten la paleta cobre clara', () {
    final paths = <String>[
      ...Directory('assets')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path)
          .where((path) => path.endsWith('bronze.svg')),
      '.agents/skills/bicimad-badge-generator/assets/bases/'
          'badge_base_bronze.svg',
    ];

    expect(paths, hasLength(8));
    for (final path in paths) {
      final svg = File(path).readAsStringSync();
      expect(svg, contains('#E4B487'), reason: path);
      expect(svg, contains('#C3834D'), reason: path);
      expect(svg, contains('#A25D31'), reason: path);
      expect(svg, contains('#EDC59B'), reason: path);
      expect(svg, contains('#92502C'), reason: path);
      expect(svg, contains('#713B20'), reason: path);
      expect(svg, isNot(contains('#D9A06E')), reason: path);
      expect(svg, isNot(contains('#F7C948')), reason: path);
      expect(svg, isNot(contains('#FFF2A8')), reason: path);
    }
  });

  test('ranking de logros agrega progreso y respeta privacidad social', () {
    final sql = File(
      'supabase/migrations/20260822010000_achievement_community_ranking.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('create or replace function public.get_achievement_ranking'),
    );
    expect(sql, contains('security definer'));
    expect(sql, contains('current_user_id uuid := auth.uid()'));
    expect(sql, contains('profile.is_public'));
    expect(sql, contains("allowed_follow.status = 'accepted'"));
    expect(sql, contains('max(achievement.progress)'));
    expect(sql, contains('coalesce(progress.metric_value, 0)'));
    expect(sql, contains('row_number() over'));
    expect(sql, contains('grant execute on function'));
    expect(sql, isNot(contains('profile.email')));
    expect(sql, isNot(contains('public.trips')));
  });

  test('emblema base bloqueado no contiene pictograma de categoria', () {
    final svg = File(
      'assets/badges/level_markers/badge_level_locked.svg',
    ).readAsStringSync();

    expect(svg, contains('viewBox="0 0 512 512"'));
    expect(RegExp('id="badge-content"').allMatches(svg), hasLength(1));
    expect(_badgeContent(svg).trim(), isEmpty);
    expect(svg, isNot(contains('<image')));
    expect(svg, isNot(contains('base64')));
    expect(svg, isNot(contains('<text')));
  });

  test('migracion persiste, deduplica y protege logros por usuario', () {
    final sql = File(
      'supabase/migrations/20260821120000_user_achievements.sql',
    ).readAsStringSync();

    expect(sql, contains('create table public.user_achievements'));
    expect(sql, contains('primary key (user_id, category_id, level_id)'));
    expect(
      sql,
      contains(
        'alter table public.user_achievements enable row level security',
      ),
    );
    expect(sql, contains('user_id = auth.uid()'));
    expect(sql, contains('refresh_profile_achievements'));
    expect(sql, contains('refresh_own_achievements'));
    expect(sql, contains('current_user_id uuid := auth.uid()'));
    expect(sql, contains('on conflict (user_id, category_id, level_id)'));
    expect(sql, contains('between 0 and 119'));
    expect(sql, contains('current_origin_id <> stage.destination_station_id'));
    expect(sql, contains('for existing_profile in select'));
    expect(
      sql,
      isNot(contains('grant insert on table public.user_achievements')),
    );
    expect(
      sql,
      isNot(contains('grant update on table public.user_achievements')),
    );
  });

  test('migracion persiste el progreso agregado exacto', () {
    final sql = File(
      'supabase/migrations/20260821200000_achievement_progress.sql',
    ).readAsStringSync();

    expect(sql, contains('add column progress integer not null default 0'));
    expect(sql, contains('refresh_profile_achievement_progress'));
    expect(sql, contains('pit_stop_progress'));
    expect(sql, contains('fast_trip_progress'));
    expect(sql, contains('favorite_station_progress'));
    expect(sql, contains('current_destination_id = stage.origin_station_id'));
    expect(sql, contains('perform public.refresh_profile_achievements'));
    expect(
      sql,
      isNot(contains('grant update on table public.user_achievements')),
    );
  });

  test('SVG de niveles conservan geometria central identica', () {
    const paths = [
      'assets/badges/pit_stops/badge_pit_stop_1_graphite.svg',
      'assets/badges/pit_stops/badge_pit_stop_10_bronze.svg',
      'assets/badges/pit_stops/badge_pit_stop_50_silver.svg',
      'assets/badges/pit_stops/badge_pit_stop_100_gold.svg',
    ];
    final contents = [for (final path in paths) File(path).readAsStringSync()];
    final badgeContents = [for (final svg in contents) _badgeContent(svg)];

    for (final svg in contents) {
      expect(svg, contains('viewBox="0 0 512 512"'));
      expect(RegExp('id="badge-content"').allMatches(svg), hasLength(1));
      expect(svg, isNot(contains('<image')));
      expect(svg, isNot(contains('base64')));
      expect(svg, isNot(contains('<text')));
      expect(svg, isNot(contains('href="http')));
    }
    for (final content in badgeContents.skip(1)) {
      expect(content, badgeContents.first);
    }
  });

  test('emblema bloqueado es neutral y no reutiliza grafito', () {
    final locked = File(
      'assets/badges/pit_stops/badge_pit_stop_locked.svg',
    ).readAsStringSync();
    final graphite = File(
      'assets/badges/pit_stops/badge_pit_stop_1_graphite.svg',
    ).readAsStringSync();

    expect(locked, contains('viewBox="0 0 512 512"'));
    expect(locked, contains('#E3E6E8'));
    expect(locked, contains('#8F979C'));
    expect(locked, isNot(graphite));
    expect(locked, isNot(contains('lock')));
  });

  test('migracion calcula viajes estrictamente por encima de 14 km/h', () {
    final sql = File(
      'supabase/migrations/20260821160000_fast_trip_achievements.sql',
    ).readAsStringSync();

    expect(sql, contains("'fast_trips_14_kmh'"));
    expect(sql, contains('/ journey.duration_seconds * 3.6 > 14.000000001'));
    expect(sql, contains('pg_temp.achievement_journeys'));
    expect(sql, contains('greatest(current_stage_count - 1, 0)'));
    expect(sql, contains('between 0 and 119'));
    expect(sql, contains('current_origin_id <> stage.destination_station_id'));
    expect(sql, contains('on conflict (user_id, category_id, level_id)'));
    expect(sql, contains('for existing_profile in select'));
  });

  test('SVG de viajes rapidos conservan el mismo champinon', () {
    const paths = [
      'assets/badges/fast_trips/badge_fast_trip_1_graphite.svg',
      'assets/badges/fast_trips/badge_fast_trip_10_bronze.svg',
      'assets/badges/fast_trips/badge_fast_trip_50_silver.svg',
      'assets/badges/fast_trips/badge_fast_trip_100_gold.svg',
    ];
    final contents = [for (final path in paths) File(path).readAsStringSync()];
    final badgeContents = [for (final svg in contents) _badgeContent(svg)];

    for (final svg in contents) {
      _expectSafeBadgeSvg(svg);
      expect(svg, contains('assets/bases/mushroom_base.svg'));
      expect(svg, contains('#244E78'));
      expect(svg, contains('#FFFFFF'));
    }
    for (final content in badgeContents.skip(1)) {
      expect(content, badgeContents.first);
    }
  });

  test('emblema rapido bloqueado conserva geometria neutral', () {
    final locked = File(
      'assets/badges/fast_trips/badge_fast_trip_locked.svg',
    ).readAsStringSync();
    final graphite = File(
      'assets/badges/fast_trips/badge_fast_trip_1_graphite.svg',
    ).readAsStringSync();

    _expectSafeBadgeSvg(locked);
    expect(locked, contains('#E3E6E8'));
    expect(locked, contains('#8F979C'));
    expect(locked, isNot(graphite));
    expect(locked, isNot(contains('<text')));
  });

  test('migracion calcula usos por estacion sobre journeys canonicos', () {
    final sql = File(
      'supabase/migrations/20260821180000_favorite_station_achievements.sql',
    ).readAsStringSync();

    expect(sql, contains("'favorite_station'"));
    expect(sql, contains("('graphite', 10)"));
    expect(sql, contains("('bronze', 50)"));
    expect(sql, contains("('silver', 200)"));
    expect(sql, contains("('gold', 500)"));
    expect(sql, contains('bicimad_public_station_code'));
    expect(sql, contains('partition by endpoint.station_key'));
    expect(sql, contains('between 0 and 119'));
    expect(sql, contains('current_origin_id <> stage.destination_station_id'));
    expect(sql, contains('refresh_profile_base_achievements'));
    expect(sql, contains('refresh_profile_station_achievement'));
    expect(sql, contains('for existing_profile in select'));
  });

  test('SVG de estacion favorita conservan corazon y anclaje identicos', () {
    const paths = [
      'assets/badges/stations/badge_favorite_station_10_graphite.svg',
      'assets/badges/stations/badge_favorite_station_50_bronze.svg',
      'assets/badges/stations/badge_favorite_station_200_silver.svg',
      'assets/badges/stations/badge_favorite_station_500_gold.svg',
    ];
    final contents = [for (final path in paths) File(path).readAsStringSync()];
    final badgeContents = [for (final svg in contents) _badgeContent(svg)];

    for (final svg in contents) {
      expect(svg, contains('viewBox="0 0 512 512"'));
      expect(RegExp('id="badge-content"').allMatches(svg), hasLength(1));
      expect(svg, contains('Material Symbols "favorite"'));
      expect(svg, contains('#244E78'));
      expect(svg, contains('#FFFFFF'));
      expect(svg, isNot(contains('<image')));
      expect(svg, isNot(contains('base64')));
      expect(svg, isNot(contains('<text')));
      expect(svg, isNot(contains('href="http')));
    }
    for (final content in badgeContents.skip(1)) {
      expect(content, badgeContents.first);
    }
  });

  test('emblema bloqueado de estacion es neutral', () {
    final locked = File(
      'assets/badges/stations/badge_favorite_station_locked.svg',
    ).readAsStringSync();
    final graphite = File(
      'assets/badges/stations/badge_favorite_station_10_graphite.svg',
    ).readAsStringSync();

    expect(locked, contains('#E3E6E8'));
    expect(locked, contains('#8F979C'));
    expect(locked, isNot(graphite));
    expect(locked, isNot(contains('<text')));
  });

  test('migracion calcula y restaura viajes de mas de 5 km', () {
    final sql = File(
      'supabase/migrations/'
      '20260901120000_long_trip_achievement_thresholds.sql',
    ).readAsStringSync();

    expect(sql, contains("'long_trips_5_km'"));
    expect(sql, contains('direct_distance_meters > 5000.0'));
    expect(sql, contains("('graphite', 1)"));
    expect(sql, contains("('bronze', 10)"));
    expect(sql, contains("('silver', 50)"));
    expect(sql, contains("('gold', 100)"));
    expect(sql, contains('pg_temp.achievement_journeys'));
    expect(sql, contains('refresh_profile_long_trip_achievement'));
    expect(sql, contains('for existing_profile in select'));
    expect(
      sql,
      isNot(contains('grant update on table public.user_achievements')),
    );
  });

  test('SVG de viajes largos conservan el mismo icono 5k', () {
    const paths = [
      'assets/badges/long_trips/badge_long_trip_1_graphite.svg',
      'assets/badges/long_trips/badge_long_trip_10_bronze.svg',
      'assets/badges/long_trips/badge_long_trip_50_silver.svg',
      'assets/badges/long_trips/badge_long_trip_100_gold.svg',
    ];
    final contents = [for (final path in paths) File(path).readAsStringSync()];
    final badgeContents = [for (final svg in contents) _badgeContent(svg)];

    for (final svg in contents) {
      _expectSafeBadgeSvg(svg);
      expect(svg, contains('assets/bases/5k_base.svg'));
      expect(svg, contains('#244E78'));
      expect(svg, contains('#FFFFFF'));
    }
    for (final content in badgeContents.skip(1)) {
      expect(content, badgeContents.first);
    }
  });

  test('emblema largo bloqueado conserva geometria neutral', () {
    final locked = File(
      'assets/badges/long_trips/badge_long_trip_locked.svg',
    ).readAsStringSync();
    final graphite = File(
      'assets/badges/long_trips/badge_long_trip_1_graphite.svg',
    ).readAsStringSync();

    _expectSafeBadgeSvg(locked);
    expect(locked, contains('#E3E6E8'));
    expect(locked, contains('#8F979C'));
    expect(locked, isNot(graphite));
  });

  test('migracion cuenta una bicicleta una vez por journey', () {
    final sql = File(
      'supabase/migrations/20260821230000_favorite_bike_achievements.sql',
    ).readAsStringSync();

    expect(sql, contains("'favorite_bike'"));
    expect(sql, contains('primary key (journey_index, bike_id)'));
    expect(sql, contains('partition by usage.bike_id'));
    expect(sql, contains("('graphite', 1)"));
    expect(sql, contains("('bronze', 2)"));
    expect(sql, contains("('silver', 3)"));
    expect(sql, contains("('gold', 5)"));
    expect(sql, contains('between 0 and 119'));
    expect(sql, contains('current_origin_id <> stage.destination_station_id'));
    expect(sql, contains('for existing_profile in select'));
    expect(
      sql,
      isNot(contains('grant update on table public.user_achievements')),
    );
  });

  test('migracion actualiza bici favorita a niveles 2 3 4 5', () {
    final sql = File(
      'supabase/migrations/20260822000000_favorite_bike_thresholds.sql',
    ).readAsStringSync();

    expect(sql, contains("('graphite', 2)"));
    expect(sql, contains("('bronze', 3)"));
    expect(sql, contains("('silver', 4)"));
    expect(sql, contains("('gold', 5)"));
    expect(
      sql,
      contains(
        "delete from public.user_achievements\nwhere category_id = 'favorite_bike'",
      ),
    );
    expect(sql, contains('perform public.refresh_profile_achievements'));
  });

  test('SVG de bici favorita conservan corazon y bicicleta identicos', () {
    const paths = [
      'assets/badges/bikes/badge_favorite_bike_2_graphite.svg',
      'assets/badges/bikes/badge_favorite_bike_3_bronze.svg',
      'assets/badges/bikes/badge_favorite_bike_4_silver.svg',
      'assets/badges/bikes/badge_favorite_bike_5_gold.svg',
    ];
    final contents = [for (final path in paths) File(path).readAsStringSync()];
    final badgeContents = [for (final svg in contents) _badgeContent(svg)];

    for (final svg in contents) {
      expect(svg, contains('viewBox="0 0 512 512"'));
      expect(RegExp('id="badge-content"').allMatches(svg), hasLength(1));
      expect(svg, contains('Material Symbols "favorite"'));
      expect(svg, contains('assets/bases/bike_base.svg'));
      expect(svg, contains('<circle cx="110" cy="220" r="78"/>'));
      expect(svg, contains('<circle cx="402" cy="220" r="78"/>'));
      expect(svg, contains('#244E78'));
      expect(svg, contains('#FFFFFF'));
      expect(svg, isNot(contains('<image')));
      expect(svg, isNot(contains('base64')));
      expect(svg, isNot(contains('<text')));
      expect(svg, isNot(contains('href="http')));
    }
    for (final content in badgeContents.skip(1)) {
      expect(content, badgeContents.first);
    }
  });

  test('emblema bloqueado de bici es neutral', () {
    final locked = File(
      'assets/badges/bikes/badge_favorite_bike_locked.svg',
    ).readAsStringSync();
    final graphite = File(
      'assets/badges/bikes/badge_favorite_bike_2_graphite.svg',
    ).readAsStringSync();

    expect(locked, contains('#E3E6E8'));
    expect(locked, contains('#8F979C'));
    expect(locked, isNot(graphite));
    expect(locked, isNot(contains('<text')));
  });
}

void _expectSafeBadgeSvg(String svg) {
  expect(svg, contains('viewBox="0 0 512 512"'));
  expect(RegExp('id="badge-content"').allMatches(svg), hasLength(1));
  expect(svg, isNot(contains('<image')));
  expect(svg, isNot(contains('base64')));
  expect(svg, isNot(contains('<text')));
  expect(svg, isNot(contains('href="http')));
  expect(svg, isNot(contains('<filter')));
}

String _badgeContent(String svg) {
  final match = RegExp(
    r'<g id="badge-content"([^>]*)>([\s\S]*?)</g>\s*</g>\s*</svg>',
  ).firstMatch(svg);
  expect(match, isNotNull);
  return '${match!.group(1)}${match.group(2)!.trim()}';
}
