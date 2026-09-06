import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la RPC agrupa Comunidad y mejores viajes en una sola consulta', () {
    final sql = File(
      'supabase/migrations/20260822020000_community_route_ranking.sql',
    ).readAsStringSync();

    expect(sql, contains('get_community_route_ranking'));
    expect(sql, contains('select follow.following_id'));
    expect(sql, contains('follow.follower_id = context.current_user_id'));
    expect(sql, contains("follow.status = 'accepted'"));
    expect(sql, contains('with recursive'));
    expect(sql, contains('between 0 and 119'));
    expect(sql, contains('previous.destination_station_id'));
    expect(sql, contains('previous.journey_origin_station_id'));
    expect(sql, contains('distinct on (candidate.user_id)'));
    expect(sql, contains('best.user_id = context.current_user_id'));
    expect(RegExp(r'from public\.trips\b').allMatches(sql), hasLength(1));
  });
}
