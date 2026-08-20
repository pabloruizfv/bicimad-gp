import '../domain/bicimad_trip.dart';
import '../domain/station_code.dart';
import '../domain/trip.dart';

class BicimadTripMapper {
  const BicimadTripMapper();

  Trip toDomainTrip({required BicimadTrip trip, required String userId}) {
    final originStationName =
        trip.originStationName ?? 'Estacion ${trip.originStationNumber}';
    final destinationStationName =
        trip.destinationStationName ??
        'Estacion ${trip.destinationStationNumber}';
    return Trip(
      id: 'bicimad-${trip.externalId}',
      externalId: trip.externalId,
      userId: userId,
      originStationId:
          canonicalStationCode(
            stationId: trip.originStationNumber,
            stationName: originStationName,
          ) ??
          trip.originStationNumber,
      originStationName: originStationName,
      destinationStationId:
          canonicalStationCode(
            stationId: trip.destinationStationNumber,
            stationName: destinationStationName,
          ) ??
          trip.destinationStationNumber,
      destinationStationName: destinationStationName,
      startedAt: trip.startedAt,
      durationSeconds: _durationSeconds(trip),
      isShared: true,
      bikeId: trip.bikeId,
      tripCost: trip.tripCost,
    );
  }

  int _durationSeconds(BicimadTrip trip) {
    final fromMinutes = (trip.durationMinutes * 60).round();
    if (fromMinutes > 0) {
      return fromMinutes;
    }

    final parts = trip.durationText.split(':');
    if (parts.length != 3) {
      return 0;
    }
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = int.tryParse(parts[2]) ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }
}
