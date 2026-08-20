import 'route_summary.dart';

enum RankingsSortMode { position, speed, tripCount }

List<RouteSummary> sortRouteSummaries(
  Iterable<RouteSummary> summaries,
  RankingsSortMode mode,
) {
  final sorted = [...summaries];
  sorted.sort(switch (mode) {
    RankingsSortMode.position => _comparePosition,
    RankingsSortMode.speed => _compareSpeed,
    RankingsSortMode.tripCount => _compareTripCount,
  });
  return sorted;
}

int _comparePosition(RouteSummary a, RouteSummary b) {
  final percentileA = a.historicalPercentile;
  final percentileB = b.historicalPercentile;
  final missingComparison = _compareMissing(percentileA, percentileB);
  if (missingComparison != 0) return missingComparison;

  final byPosition = (percentileA ?? 0).compareTo(percentileB ?? 0);
  if (byPosition != 0) return byPosition;
  return _compareSpeed(a, b);
}

int _compareSpeed(RouteSummary a, RouteSummary b) {
  final speedA = a.personalBestSpeedKmh;
  final speedB = b.personalBestSpeedKmh;
  final missingComparison = _compareMissing(speedA, speedB);
  if (missingComparison != 0) return missingComparison;

  final bySpeed = (speedB ?? 0).compareTo(speedA ?? 0);
  if (bySpeed != 0) return bySpeed;
  return a.originStationName.compareTo(b.originStationName);
}

int _compareTripCount(RouteSummary a, RouteSummary b) {
  final byTripCount = b.personalTripCount.compareTo(a.personalTripCount);
  if (byTripCount != 0) return byTripCount;
  return _comparePosition(a, b);
}

int _compareMissing(num? a, num? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return 0;
}
