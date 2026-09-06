import 'trip.dart';

const _discardedStationNames = {'bici mal anclada', 'ubicacion no permitida'};

bool isDiscardedBicimadStationName(String stationName) {
  var normalized = stationName.trim().toLowerCase();
  normalized = normalized.replaceFirst(RegExp(r'^\d+\s*-\s*'), '');
  normalized = normalized
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return _discardedStationNames.contains(normalized);
}

bool isCountableBicimadStage(Trip trip) {
  return trip.originStationId != trip.destinationStationId &&
      trip.durationSeconds > 0 &&
      !isDiscardedBicimadStationName(trip.originStationName) &&
      !isDiscardedBicimadStationName(trip.destinationStationName);
}
