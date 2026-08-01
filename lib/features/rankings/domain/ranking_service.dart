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
    required Iterable<CommunityUser> users,
    required String currentUserId,
  }) {
    final routes = <RouteKey, List<Trip>>{};
    for (final trip in myTrips) {
      final key = RouteKey(
        originStationId: trip.originStationId,
        destinationStationId: trip.destinationStationId,
      );
      routes.putIfAbsent(key, () => <Trip>[]).add(trip);
    }

    final summaries = <RouteSummary>[];
    for (final entry in routes.entries) {
      final personalBest = entry.value.reduce(
        (best, trip) =>
            trip.durationSeconds < best.durationSeconds ? trip : best,
      );
      final ranking = buildRouteRanking(
        trips: sharedTrips,
        users: users,
        currentUserId: currentUserId,
        originStationId: entry.key.originStationId,
        destinationStationId: entry.key.destinationStationId,
      );

      summaries.add(
        RouteSummary(
          originStationId: personalBest.originStationId,
          originStationName: personalBest.originStationName,
          destinationStationId: personalBest.destinationStationId,
          destinationStationName: personalBest.destinationStationName,
          personalBestDurationSeconds: personalBest.durationSeconds,
          currentUserPosition: ranking.currentUserPosition,
          totalUsers: ranking.totalUsers,
        ),
      );
    }

    summaries.sort(
      (a, b) => a.originStationName.compareTo(b.originStationName),
    );
    return summaries;
  }
}
