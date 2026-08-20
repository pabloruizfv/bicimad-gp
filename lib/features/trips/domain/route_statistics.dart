import 'trip.dart';

class RouteStatistics {
  const RouteStatistics({
    required this.totalTrips,
    required this.validTripCount,
    required this.bestDurationSeconds,
    required this.averageDurationSeconds,
    required this.medianDurationSeconds,
    required this.latestDurationSeconds,
    required this.bestTripIds,
  });

  factory RouteStatistics.fromTrips(Iterable<Trip> trips) {
    final allTrips = trips.toList();
    final validTrips = allTrips
        .where((trip) => trip.durationSeconds > 0)
        .toList(growable: false);

    if (validTrips.isEmpty) {
      return RouteStatistics(
        totalTrips: allTrips.length,
        validTripCount: 0,
        bestDurationSeconds: null,
        averageDurationSeconds: null,
        medianDurationSeconds: null,
        latestDurationSeconds: null,
        bestTripIds: const {},
      );
    }

    final sortedDurations =
        validTrips.map((trip) => trip.durationSeconds).toList()..sort();
    final bestDuration = sortedDurations.first;
    final totalDuration = sortedDurations.fold<int>(
      0,
      (sum, duration) => sum + duration,
    );
    final middle = sortedDurations.length ~/ 2;
    final median = sortedDurations.length.isOdd
        ? sortedDurations[middle].toDouble()
        : (sortedDurations[middle - 1] + sortedDurations[middle]) / 2;
    final latestValidTrip = validTrips.reduce(
      (latest, trip) =>
          trip.startedAt.isAfter(latest.startedAt) ? trip : latest,
    );

    return RouteStatistics(
      totalTrips: allTrips.length,
      validTripCount: validTrips.length,
      bestDurationSeconds: bestDuration,
      averageDurationSeconds: totalDuration / validTrips.length,
      medianDurationSeconds: median,
      latestDurationSeconds: latestValidTrip.durationSeconds,
      bestTripIds: {
        for (final trip in validTrips)
          if (trip.durationSeconds == bestDuration) trip.id,
      },
    );
  }

  final int totalTrips;
  final int validTripCount;
  final int? bestDurationSeconds;
  final double? averageDurationSeconds;
  final double? medianDurationSeconds;
  final int? latestDurationSeconds;
  final Set<String> bestTripIds;

  bool isBestTrip(Trip trip) => bestTripIds.contains(trip.id);
}
