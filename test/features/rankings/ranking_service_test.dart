import 'package:bicimad_social/features/rankings/domain/ranking_service.dart';
import 'package:bicimad_social/features/rankings/domain/rankings_sort.dart';
import 'package:bicimad_social/features/rankings/domain/route_summary.dart';
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

    test('orders route summaries by ranking and then speed', () {
      final summaries = service.buildUserRouteSummaries(
        myTrips: [
          _trip(
            'fast-tie',
            'current-user',
            300,
            origin: 'C',
            destination: 'D',
            distance: 1500,
          ),
          _trip(
            'slow-tie',
            'current-user',
            300,
            origin: 'E',
            destination: 'F',
            distance: 900,
          ),
          _trip(
            'winner',
            'current-user',
            290,
            origin: 'A',
            destination: 'B',
            distance: 700,
          ),
        ],
        sharedTrips: [
          _trip('winner-shared', 'current-user', 290),
          _trip('fast-shared', 'ana', 280, origin: 'C', destination: 'D'),
          _trip(
            'fast-current',
            'current-user',
            300,
            origin: 'C',
            destination: 'D',
          ),
          _trip('slow-shared', 'ana', 280, origin: 'E', destination: 'F'),
          _trip(
            'slow-current',
            'current-user',
            300,
            origin: 'E',
            destination: 'F',
          ),
        ],
        currentUserId: 'current-user',
      );

      expect(summaries.map((summary) => summary.originStationId), [
        'A',
        'C',
        'E',
      ]);
      expect(
        summaries[1].personalBestSpeedKmh,
        greaterThan(summaries[2].personalBestSpeedKmh!),
      );
      expect(summaries.first.personalBestStartedAt, DateTime(2026, 7, 20, 8));
    });

    test('agrupa A a B separado de B a A y recorre shared una sola vez', () {
      var sharedTraversals = 0;
      final shared = [
        _trip('ab-current', 'current-user', 300),
        _trip('ba-current', 'current-user', 320, origin: 'B', destination: 'A'),
      ];

      Iterable<Trip> countedShared() sync* {
        sharedTraversals += 1;
        yield* shared;
      }

      final summaries = service.buildUserRouteSummaries(
        myTrips: shared,
        sharedTrips: countedShared(),
        currentUserId: 'current-user',
      );

      expect(summaries, hasLength(2));
      expect(
        summaries
            .map(
              (summary) =>
                  '${summary.originStationId}->${summary.destinationStationId}',
            )
            .toSet(),
        {'A->B', 'B->A'},
      );
      expect(sharedTraversals, 1);
    });
  });

  group('orden de Rankings', () {
    final summaries = [
      _summary('A', percentile: 84, speed: 14, tripCount: 2),
      _summary('B', percentile: 50, speed: 11, tripCount: 5),
      _summary('C', percentile: null, speed: 18, tripCount: 3),
    ];

    test('ordena por percentil ascendente y deja ausentes al final', () {
      final sorted = sortRouteSummaries(summaries, RankingsSortMode.position);

      expect(sorted.map((summary) => summary.originStationId), ['B', 'A', 'C']);
    });

    test('ordena por velocidad descendente', () {
      final sorted = sortRouteSummaries(summaries, RankingsSortMode.speed);

      expect(sorted.map((summary) => summary.originStationId), ['C', 'A', 'B']);
    });

    test('ordena por numero de viajes descendente', () {
      final sorted = sortRouteSummaries(summaries, RankingsSortMode.tripCount);

      expect(sorted.map((summary) => summary.originStationId), ['B', 'C', 'A']);
    });
  });
}

RouteSummary _summary(
  String stationId, {
  required double? percentile,
  required double? speed,
  required int tripCount,
}) {
  return RouteSummary(
    originStationId: stationId,
    originStationName: stationId,
    destinationStationId: 'Z',
    destinationStationName: 'Z',
    personalBestDurationSeconds: 300,
    personalBestDistanceMeters: 1000,
    personalBestSpeedKmh: speed,
    personalTripCount: tripCount,
    historicalPercentile: percentile,
    currentUserPosition: null,
    totalUsers: 1,
  );
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
  double? distance,
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
    directDistanceMeters: distance,
  );
}
