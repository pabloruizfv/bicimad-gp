class RouteSummary {
  const RouteSummary({
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.personalBestDurationSeconds,
    required this.personalBestDistanceMeters,
    required this.personalBestSpeedKmh,
    required this.personalTripCount,
    this.personalBestStartedAt,
    this.historicalPercentile,
    required this.currentUserPosition,
    required this.totalUsers,
  });

  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final int personalBestDurationSeconds;
  final double? personalBestDistanceMeters;
  final double? personalBestSpeedKmh;
  final int personalTripCount;
  final DateTime? personalBestStartedAt;
  final double? historicalPercentile;
  final int? currentUserPosition;
  final int totalUsers;

  RouteSummary copyWith({double? historicalPercentile}) {
    return RouteSummary(
      originStationId: originStationId,
      originStationName: originStationName,
      destinationStationId: destinationStationId,
      destinationStationName: destinationStationName,
      personalBestDurationSeconds: personalBestDurationSeconds,
      personalBestDistanceMeters: personalBestDistanceMeters,
      personalBestSpeedKmh: personalBestSpeedKmh,
      personalTripCount: personalTripCount,
      personalBestStartedAt: personalBestStartedAt,
      historicalPercentile: historicalPercentile ?? this.historicalPercentile,
      currentUserPosition: currentUserPosition,
      totalUsers: totalUsers,
    );
  }
}
