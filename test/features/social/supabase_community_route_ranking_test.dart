import 'dart:convert';

import 'package:bicimad_social/features/social/data/supabase_social_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('obtiene el ranking de ruta con una sola RPC agregada', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://project.example.test',
      'fake-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode([
            {
              'user_id': 'followed-user',
              'display_name': 'Laura',
              'username': 'laura',
              'avatar_key': '2.png',
              'duration_milliseconds': 411231,
              'direct_distance_meters': 1500.0,
              'started_at': null,
              'is_current_user': false,
            },
            {
              'user_id': 'current-user',
              'display_name': 'Pablo',
              'username': 'pablo',
              'avatar_key': '1.png',
              'duration_milliseconds': 420000,
              'direct_distance_meters': 1500.0,
              'started_at': '2026-08-20T10:00:00Z',
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

    final ranking = await SupabaseSocialRepository(client)
        .getCommunityRouteRanking(
          originStationId: '40',
          destinationStationId: '172',
        );

    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/get_community_route_ranking',
    );
    expect(jsonDecode(requests.single.body), {
      'p_origin_station_id': '40',
      'p_destination_station_id': '172',
    });
    expect(ranking.entries, hasLength(2));
    expect(ranking.entries.first.durationMilliseconds, 411231);
    expect(ranking.currentUserEntry?.startedAt, isNotNull);
  });
}
