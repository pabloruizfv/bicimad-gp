class RouteKey {
  const RouteKey({
    required this.originStationId,
    required this.destinationStationId,
  });

  final String originStationId;
  final String destinationStationId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RouteKey &&
            originStationId == other.originStationId &&
            destinationStationId == other.destinationStationId;
  }

  @override
  int get hashCode => Object.hash(originStationId, destinationStationId);
}
