class BicimadTrip {
  const BicimadTrip({
    required this.externalId,
    required this.originStationNumber,
    required this.originStationName,
    required this.destinationStationNumber,
    required this.destinationStationName,
    required this.startedAt,
    required this.endedAt,
    required this.durationMinutes,
    required this.durationText,
    this.bikeId,
    this.tripCost,
  });

  final String externalId;
  final String originStationNumber;
  final String? originStationName;
  final String destinationStationNumber;
  final String? destinationStationName;
  final DateTime startedAt;
  final DateTime endedAt;
  final double durationMinutes;
  final String durationText;
  final String? bikeId;
  final String? tripCost;
}
