import '../../../core/utils/geo_utils.dart';
import '../../../core/models/profile_statistics_values.dart';
import '../../stations/domain/station_catalog.dart';
import 'canonical_trip_statistics.dart';
import 'trip.dart';

class TripMetricsEnricher {
  const TripMetricsEnricher();

  Trip enrich(Trip trip, StationCatalog catalog) {
    if (trip.directDistanceMeters != null &&
        trip.originLatitude != null &&
        trip.originLongitude != null &&
        trip.destinationLatitude != null &&
        trip.destinationLongitude != null) {
      return trip;
    }

    final origin = catalog.resolve(
      stationId: trip.originStationId,
      stationName: trip.originStationName,
    );
    final destination = catalog.resolve(
      stationId: trip.destinationStationId,
      stationName: trip.destinationStationName,
    );
    if (origin == null || destination == null) {
      return trip;
    }

    final distance = haversineDistanceMeters(
      fromLatitude: origin.latitude,
      fromLongitude: origin.longitude,
      toLatitude: destination.latitude,
      toLongitude: destination.longitude,
    );
    return trip.copyWith(
      originLatitude: origin.latitude,
      originLongitude: origin.longitude,
      destinationLatitude: destination.latitude,
      destinationLongitude: destination.longitude,
      directDistanceMeters: distance,
    );
  }
}

class GeneralTripMetrics implements ProfileStatisticsValues {
  const GeneralTripMetrics({
    required this.totalTrips,
    required this.distinctTripDays,
    required this.totalDurationSeconds,
    required this.totalDirectDistanceMeters,
    required this.tripsWithDistance,
    required this.averageDurationSeconds,
    required this.equivalentAverageSpeedKmh,
    required this.firstTripAt,
    required this.lastTripAt,
    required this.coverageDays,
    required this.periodCount,
  });

  factory GeneralTripMetrics.fromTrips({
    required List<Trip> trips,
    required List<CoverageInterval> coverageIntervals,
  }) {
    final canonical = CanonicalTripStatistics.fromJourneys(trips);

    return GeneralTripMetrics(
      totalTrips: canonical.totalTrips,
      distinctTripDays: canonical.distinctTripDays,
      totalDurationSeconds: canonical.totalDurationSeconds,
      totalDirectDistanceMeters: canonical.totalDistanceMeters,
      tripsWithDistance: canonical.tripsWithDistance,
      averageDurationSeconds: canonical.averageDurationSeconds,
      equivalentAverageSpeedKmh: canonical.equivalentAverageSpeedKmh,
      firstTripAt: canonical.firstTripAt,
      lastTripAt: canonical.lastTripAt,
      coverageDays: coverageIntervals.fold<int>(
        0,
        (sum, interval) => sum + interval.coveredDays,
      ),
      periodCount: coverageIntervals.length,
    );
  }

  @override
  final int totalTrips;
  final int distinctTripDays;
  @override
  final int totalDurationSeconds;
  final double totalDirectDistanceMeters;
  @override
  final int tripsWithDistance;
  final double? averageDurationSeconds;
  @override
  final double? equivalentAverageSpeedKmh;
  final DateTime? firstTripAt;
  final DateTime? lastTripAt;
  final int coverageDays;
  final int periodCount;

  @override
  double get totalDistanceMeters => totalDirectDistanceMeters;

  @override
  int get historySpanDays {
    final first = firstTripAt;
    final last = lastTripAt;
    if (first == null || last == null) {
      return 0;
    }
    final firstDay = DateTime(first.year, first.month, first.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    return lastDay.difference(firstDay).inDays + 1;
  }
}

class CoverageInterval {
  const CoverageInterval({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  int get coveredDays {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.difference(startDay).inDays + 1;
  }

  bool overlaps(CoverageInterval other) {
    return !end.isBefore(other.start) && !start.isAfter(other.end);
  }

  CoverageInterval merge(CoverageInterval other) {
    return CoverageInterval(
      start: start.isBefore(other.start) ? start : other.start,
      end: end.isAfter(other.end) ? end : other.end,
    );
  }

  Map<String, Object?> toJson() {
    return {'start': start.toIso8601String(), 'end': end.toIso8601String()};
  }

  static CoverageInterval? fromJson(Map<String, Object?> json) {
    final start = json['start'];
    final end = json['end'];
    if (start is! String || end is! String) {
      return null;
    }
    final parsedStart = DateTime.tryParse(start);
    final parsedEnd = DateTime.tryParse(end);
    if (parsedStart == null || parsedEnd == null) {
      return null;
    }
    return CoverageInterval(start: parsedStart, end: parsedEnd);
  }
}

List<CoverageInterval> mergeCoverageForImport({
  required Iterable<CoverageInterval> existing,
  required Iterable<Trip> importedTrips,
  required Set<String> knownTripKeysBeforeImport,
}) {
  final imported = importedTrips.toList(growable: false);
  if (imported.isEmpty) {
    return existing.toList()..sort((a, b) => a.start.compareTo(b.start));
  }
  final sortedImported = [...imported]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final importedInterval = CoverageInterval(
    start: sortedImported.first.startedAt,
    end: sortedImported.last.startedAt,
  );
  final importedKeys = {
    for (final trip in imported) '${trip.userId}:${trip.externalId}',
  };
  final hasKnownOverlap = importedKeys.any(knownTripKeysBeforeImport.contains);
  return mergeCoverageForRange(
    existing: existing,
    importedStart: importedInterval.start,
    importedEnd: importedInterval.end,
    overlapsKnownTrips: hasKnownOverlap,
  );
}

List<CoverageInterval> mergeCoverageForRange({
  required Iterable<CoverageInterval> existing,
  required DateTime importedStart,
  required DateTime importedEnd,
  required bool overlapsKnownTrips,
}) {
  final intervals = existing.toList(growable: true);
  final importedInterval = CoverageInterval(
    start: importedStart.isBefore(importedEnd) ? importedStart : importedEnd,
    end: importedStart.isAfter(importedEnd) ? importedStart : importedEnd,
  );

  if (!overlapsKnownTrips) {
    intervals.add(importedInterval);
    return intervals..sort((a, b) => a.start.compareTo(b.start));
  }

  var merged = importedInterval;
  final remaining = <CoverageInterval>[];
  for (final interval in intervals) {
    if (interval.overlaps(merged)) {
      merged = merged.merge(interval);
    } else {
      remaining.add(interval);
    }
  }
  remaining.add(merged);
  return remaining..sort((a, b) => a.start.compareTo(b.start));
}
