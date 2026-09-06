import 'dart:convert';

import 'package:bicimad_social/features/social/data/supabase_social_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('consulta y convierte el ranking agregado sin cargar viajes', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://project.example.test',
      'fake-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode([
            {
              'rank_position': 1,
              'user_id': 'user-a',
              'display_name': 'Laura',
              'avatar_key': '1.png',
              'metric_value': 180,
              'total_users': 2,
              'is_current_user': false,
            },
            {
              'rank_position': 2,
              'user_id': 'current-user',
              'display_name': 'Pablo',
              'avatar_key': '2.png',
              'metric_value': 74,
              'total_users': 2,
              'is_current_user': true,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final ranking = await SupabaseSocialRepository(
      client,
    ).getAchievementRanking('pit_stops');

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/rest/v1/rpc/get_achievement_ranking');
    expect(jsonDecode(requests.single.body), {'p_category_id': 'pit_stops'});
    expect(ranking.totalUsers, 2);
    expect(ranking.entries, hasLength(2));
    expect(ranking.entries.first.value, 180);
    expect(ranking.currentUserEntry?.rank, 2);
    expect(ranking.currentUserTopPercent, 100);
  });
}
