import '../../trips/domain/community_user.dart';
import '../../trips/domain/trip.dart';
import 'ranking_entry.dart';
import 'route_key.dart';
import 'route_ranking.dart';
import 'route_summary.dart';

class RankingService {
  const RankingService();

  Map<String, Trip> bestTripByUserForRoute({
    required Iterable<Trip> trips,
    required String originStationId,
    required String destinationStationId,
  }) {
    final bestByUser = <String, Trip>{};

    for (final trip in trips.where(
      (trip) =>
          trip.isShared &&
          trip.matchesRoute(
            originStationId: originStationId,
            destinationStationId: destinationStationId,
          ),
    )) {
      final currentBest = bestByUser[trip.userId];
      if (currentBest == null ||
          trip.durationSeconds < currentBest.durationSeconds) {
        bestByUser[trip.userId] = trip;
      }
    }

    return bestByUser;
  }

  RouteRanking buildRouteRanking({
    required Iterable<Trip> trips,
    required Iterable<CommunityUser> users,
    required String currentUserId,
    required String originStationId,
    required String destinationStationId,
  }) {
    final routeTrips = trips
        .where(
          (trip) =>
              trip.isShared &&
              trip.matchesRoute(
                originStationId: originStationId,
                destinationStationId: destinationStationId,
              ),
        )
        .toList();

    final sampleTrip =
        routeTrips.firstOrNull ??
        trips.firstWhere(
          (trip) => trip.matchesRoute(
            originStationId: originStationId,
            destinationStationId: destinationStationId,
          ),
        );
    final usersById = {for (final user in users) user.id: user};
    final bestByUser =
        bestTripByUserForRoute(
            trips: routeTrips,
            originStationId: originStationId,
            destinationStationId: destinationStationId,
          ).values.toList()
          ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

    final entries = <RankingEntry>[];
    for (var index = 0; index < bestByUser.length; index++) {
      final trip = bestByUser[index];
      final user = usersById[trip.userId];
      entries.add(
        RankingEntry(
          userId: trip.userId,
          displayName: user?.displayName ?? 'Usuario',
          bestDurationSeconds: trip.durationSeconds,
          position: index + 1,
          isCurrentUser: trip.userId == currentUserId,
        ),
      );
    }

    final currentEntry = entries
        .where((entry) => entry.userId == currentUserId)
        .firstOrNull;

    return RouteRanking(
      originStationId: originStationId,
      originStationName: sampleTrip.originStationName,
      destinationStationId: destinationStationId,
      destinationStationName: sampleTrip.destinationStationName,
      entries: entries,
      currentUserPosition: currentEntry?.position,
      totalUsers: entries.length,
    );
  }

  double percentOfCommunityTripsSlower({
    required Trip trip,
    required Iterable<Trip> sharedTrips,
  }) {
    final comparableTrips = sharedTrips
        .where(
          (candidate) =>
              candidate.isShared &&
              candidate.matchesRoute(
                originStationId: trip.originStationId,
                destinationStationId: trip.destinationStationId,
              ),
        )
        .toList();

    if (comparableTrips.isEmpty) {
      return 0;
    }

    final slowerTrips = comparableTrips
        .where((candidate) => candidate.durationSeconds > trip.durationSeconds)
        .length;

    return slowerTrips * 100 / comparableTrips.length;
  }

  Trip? personalBestForRoute({
    required Iterable<Trip> trips,
    required Trip targetTrip,
  }) {
    final routeTrips =
        trips
            .where(
              (trip) =>
                  trip.userId == targetTrip.userId &&
                  trip.matchesRoute(
                    originStationId: targetTrip.originStationId,
                    destinationStationId: targetTrip.destinationStationId,
                  ),
            )
            .toList()
          ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

    return routeTrips.firstOrNull;
  }

  bool isPersonalRecord({
    required Iterable<Trip> trips,
    required Trip targetTrip,
  }) {
    final best = personalBestForRoute(trips: trips, targetTrip: targetTrip);
    return best?.id == targetTrip.id;
  }

  List<RouteSummary> buildUserRouteSummaries({
    required Iterable<Trip> myTrips,
    required Iterable<Trip> sharedTrips,
    required String currentUserId,
  }) {
    final personalRoutes = <RouteKey, List<Trip>>{};
    for (final trip in myTrips) {
      final key = RouteKey(
        originStationId: trip.originStationId,
        destinationStationId: trip.destinationStationId,
      );
      personalRoutes.putIfAbsent(key, () => <Trip>[]).add(trip);
    }

    final sharedBestByRouteAndUser = <RouteKey, Map<String, Trip>>{};
    for (final trip in sharedTrips) {
      if (!trip.isShared) {
        continue;
      }
      final key = RouteKey(
        originStationId: trip.originStationId,
        destinationStationId: trip.destinationStationId,
      );
      final bestByUser = sharedBestByRouteAndUser.putIfAbsent(
        key,
        () => <String, Trip>{},
      );
      final currentBest = bestByUser[trip.userId];
      if (currentBest == null ||
          trip.durationSeconds < currentBest.durationSeconds) {
        bestByUser[trip.userId] = trip;
      }
    }

    final summaries = <RouteSummary>[];
    for (final entry in personalRoutes.entries) {
      final personalBest = entry.value.reduce(
        (best, trip) =>
            trip.durationSeconds < best.durationSeconds ? trip : best,
      );
      final rankedTrips =
          sharedBestByRouteAndUser[entry.key]?.values.toList() ?? <Trip>[];
      rankedTrips.sort(
        (first, second) =>
            first.durationSeconds.compareTo(second.durationSeconds),
      );
      final currentUserIndex = rankedTrips.indexWhere(
        (trip) => trip.userId == currentUserId,
      );

      summaries.add(
        RouteSummary(
          originStationId: personalBest.originStationId,
          originStationName: personalBest.originStationName,
          destinationStationId: personalBest.destinationStationId,
          destinationStationName: personalBest.destinationStationName,
          personalBestDurationSeconds: personalBest.durationSeconds,
          personalBestDistanceMeters: personalBest.directDistanceMeters,
          originLatitude: personalBest.originLatitude,
          originLongitude: personalBest.originLongitude,
          destinationLatitude: personalBest.destinationLatitude,
          destinationLongitude: personalBest.destinationLongitude,
          personalBestSpeedKmh: personalBest.equivalentAverageSpeedKmh,
          personalTripCount: entry.value.length,
          personalBestStartedAt: personalBest.startedAt,
          currentUserPosition: currentUserIndex < 0
              ? null
              : currentUserIndex + 1,
          totalUsers: rankedTrips.length,
        ),
      );
    }

    summaries.sort(_compareRouteSummaries);
    return summaries;
  }

  int _compareRouteSummaries(RouteSummary a, RouteSummary b) {
    final positionA = a.currentUserPosition ?? 1 << 30;
    final positionB = b.currentUserPosition ?? 1 << 30;
    final byPosition = positionA.compareTo(positionB);
    if (byPosition != 0) {
      return byPosition;
    }

    final speedA = a.personalBestSpeedKmh ?? -1;
    final speedB = b.personalBestSpeedKmh ?? -1;
    final bySpeed = speedB.compareTo(speedA);
    if (bySpeed != 0) {
      return bySpeed;
    }

    return a.originStationName.compareTo(b.originStationName);
  }
}
