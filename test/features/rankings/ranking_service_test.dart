import 'package:bicimad_social/features/rankings/domain/ranking_service.dart';
import 'package:bicimad_social/features/trips/domain/community_user.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = RankingService();
  final users = [
    CommunityUser(
      id: 'current-user',
      externalUserId: 'external-current',
      displayName: 'Pablo',
      createdAt: DateTime(2026, 7, 1),
    ),
    CommunityUser(
      id: 'ana',
      externalUserId: 'external-ana',
      displayName: 'Ana',
      createdAt: DateTime(2026, 7, 1),
    ),
    CommunityUser(
      id: 'marcos',
      externalUserId: 'external-marcos',
      displayName: 'Marcos',
      createdAt: DateTime(2026, 7, 1),
    ),
  ];

  group('RankingService', () {
    test('groups trips by user and keeps only the best duration', () {
      final bestByUser = service.bestTripByUserForRoute(
        trips: _trips,
        originStationId: 'A',
        destinationStationId: 'B',
      );

      expect(bestByUser, hasLength(3));
      expect(bestByUser['current-user']!.durationSeconds, 430);
      expect(bestByUser['ana']!.durationSeconds, 390);
      expect(bestByUser['marcos']!.durationSeconds, 410);
    });

    test('sorts ranking from fastest to slowest', () {
      final ranking = service.buildRouteRanking(
        trips: _trips,
        users: users,
        currentUserId: 'current-user',
        originStationId: 'A',
        destinationStationId: 'B',
      );

      expect(ranking.entries.map((entry) => entry.displayName), [
        'Ana',
        'Marcos',
        'Pablo',
      ]);
      expect(ranking.entries.map((entry) => entry.bestDurationSeconds), [
        390,
        410,
        430,
      ]);
    });

    test('assigns current user position', () {
      final ranking = service.buildRouteRanking(
        trips: _trips,
        users: users,
        currentUserId: 'current-user',
        originStationId: 'A',
        destinationStationId: 'B',
      );

      expect(ranking.currentUserPosition, 3);
      expect(
        ranking.entries.singleWhere((entry) => entry.isCurrentUser).userId,
        'current-user',
      );
    });

    test('calculates percentage of community trips that are slower', () {
      final trip = _trip('target', 'current-user', 430);
      final percent = service.percentOfCommunityTripsSlower(
        trip: trip,
        sharedTrips: _trips,
      );

      expect(percent, closeTo(20, 0.01));
    });
  });
}

final _trips = [
  _trip('p-1', 'current-user', 450),
  _trip('p-2', 'current-user', 430),
  _trip('a-1', 'ana', 390),
  _trip('a-2', 'ana', 420),
  _trip('m-1', 'marcos', 410),
  _trip('other-route', 'ana', 250, origin: 'B', destination: 'A'),
];

Trip _trip(
  String id,
  String userId,
  int durationSeconds, {
  String origin = 'A',
  String destination = 'B',
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: userId,
    originStationId: origin,
    originStationName: origin,
    destinationStationId: destination,
    destinationStationName: destination,
    startedAt: DateTime(2026, 7, 20, 8),
    durationSeconds: durationSeconds,
    isShared: true,
  );
}
