class RouteSummary {
  const RouteSummary({
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.personalBestDurationSeconds,
    required this.currentUserPosition,
    required this.totalUsers,
  });

  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final int personalBestDurationSeconds;
  final int? currentUserPosition;
  final int totalUsers;
}
