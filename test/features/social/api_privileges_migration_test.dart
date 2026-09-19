import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260906120000_harden_api_privileges.sql',
  ).readAsStringSync();
  final revoked = migration
      .split('revoke all on function')[1]
      .split('from public, anon, authenticated;')[0];
  final granted = migration.split('grant execute on function')[1];

  test('covers every existing function, including renamed helpers', () {
    final names = <String>{};
    for (final file in Directory(
      'supabase/migrations',
    ).listSync().whereType<File>()) {
      final sql = file.readAsStringSync();
      names.addAll(
        RegExp(
          r'create (?:or replace )?function public\.(\w+)\(',
          caseSensitive: false,
        ).allMatches(sql).map((match) => match[1]!),
      );
      names.addAll(
        RegExp(r'rename to (\w+);').allMatches(sql).map((match) => match[1]!),
      );
    }
    for (final name in names) {
      expect(revoked, contains('public.$name('), reason: name);
    }
  });

  test(
    'only public entry points are granted, never arbitrary-user helpers',
    () {
      for (final name in [
        'get_best_route_times_for_users',
        'refresh_profile_stats',
        'refresh_profile_base_achievements',
        'refresh_profile_achievements',
        'refresh_profile_previous_achievement_levels',
        'refresh_profile_levels_before_favorite_bike',
      ]) {
        expect(granted, isNot(contains('public.$name(')));
      }
      for (final name in [
        'get_community_route_ranking',
        'get_head_to_head',
        'get_social_profile',
        'upsert_own_trips',
        'delete_own_account',
        'refresh_own_achievements',
      ]) {
        expect(granted, contains('public.$name('));
      }
      expect(granted, contains('to authenticated;'));
      expect(migration, isNot(contains('alter policy')));
      expect(migration, isNot(contains('delete from')));
    },
  );
}
