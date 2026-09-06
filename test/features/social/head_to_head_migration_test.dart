import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cara a cara reutiliza la derivacion de rutas y respeta privacidad', () {
    final sql = File(
      'supabase/migrations/20260822030000_head_to_head.sql',
    ).readAsStringSync();

    expect(sql, contains('get_best_route_times_for_users'));
    expect(sql, contains('get_community_route_ranking'));
    expect(sql, contains('get_head_to_head'));
    expect(sql, contains("f.status = 'accepted'"));
    expect(sql, contains('p.is_public'));
    expect(sql, contains('between 0 and 119'));
    expect(sql, contains('distinct on (candidate.user_id'));
    expect(sql, contains('grant execute on function public.get_head_to_head'));
    expect(sql, isNot(contains('started_at timestamptz, other')));
  });
}
