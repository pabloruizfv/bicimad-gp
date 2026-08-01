class Trip {
  const Trip({
    required this.id,
    required this.externalId,
    required this.userId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.startedAt,
    required this.durationSeconds,
    required this.isShared,
  });

  final String id;
  final String externalId;
  final String userId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final DateTime startedAt;
  final int durationSeconds;
  final bool isShared;

  bool matchesRoute({
    required String originStationId,
    required String destinationStationId,
  }) {
    return this.originStationId == originStationId &&
        this.destinationStationId == destinationStationId;
  }
}
