import '../../../core/models/profile_statistics_values.dart';
import 'trip.dart';

class CanonicalTripStatistics implements ProfileStatisticsValues {
  const CanonicalTripStatistics({
    required this.totalTrips,
    required this.historySpanDays,
    required this.distinctTripDays,
    required this.totalDurationSeconds,
    required this.totalDistanceMeters,
    required this.tripsWithDistance,
    required this.averageDurationSeconds,
    required this.equivalentAverageSpeedKmh,
    required this.firstTripAt,
    required this.lastTripAt,
  });

  factory CanonicalTripStatistics.fromJourneys(Iterable<Trip> journeys) {
    final valid =
        journeys
            .where(
              (journey) =>
                  journey.durationSeconds > 0 &&
                  journey.originStationId != journey.destinationStationId,
            )
            .toList(growable: false)
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final totalDuration = valid.fold<int>(
      0,
      (sum, journey) => sum + journey.durationSeconds,
    );
    final withDistance = valid
        .where((journey) => journey.directDistanceMeters != null)
        .toList(growable: false);
    final totalDistance = withDistance.fold<double>(
      0,
      (sum, journey) => sum + journey.directDistanceMeters!,
    );
    final distinctDays = {
      for (final journey in valid) _dateOnly(journey.startedAt),
    };
    final first = valid.isEmpty ? null : valid.first.startedAt;
    final last = valid.isEmpty ? null : valid.last.startedAt;

    return CanonicalTripStatistics(
      totalTrips: valid.length,
      historySpanDays: _inclusiveDays(first, last),
      distinctTripDays: distinctDays.length,
      totalDurationSeconds: totalDuration,
      totalDistanceMeters: totalDistance,
      tripsWithDistance: withDistance.length,
      averageDurationSeconds: valid.isEmpty
          ? null
          : totalDuration / valid.length,
      equivalentAverageSpeedKmh: totalDuration == 0
          ? null
          : totalDistance / totalDuration * 3.6,
      firstTripAt: first,
      lastTripAt: last,
    );
  }

  @override
  final int totalTrips;
  @override
  final int historySpanDays;
  final int distinctTripDays;
  @override
  final int totalDurationSeconds;
  @override
  final double totalDistanceMeters;
  @override
  final int tripsWithDistance;
  final double? averageDurationSeconds;
  @override
  final double? equivalentAverageSpeedKmh;
  final DateTime? firstTripAt;
  final DateTime? lastTripAt;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int _inclusiveDays(DateTime? first, DateTime? last) {
  if (first == null || last == null) {
    return 0;
  }
  return _dateOnly(last).difference(_dateOnly(first)).inDays + 1;
}
