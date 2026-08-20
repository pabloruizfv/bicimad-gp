import 'package:bicimad_social/features/trips/data/bicimad_trip_mapper.dart';
import 'package:bicimad_social/features/trips/domain/bicimad_trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa el codigo publico del nombre como identificador de estacion', () {
    final trip = const BicimadTripMapper().toDomainTrip(
      userId: 'current-user',
      trip: BicimadTrip(
        externalId: 'trip-1',
        originStationNumber: 'internal-origin',
        originStationName: '34 - Jacinto Benavente',
        destinationStationNumber: 'internal-destination',
        destinationStationName: '164 - Paseo de las Delicias',
        startedAt: DateTime(2026, 8, 3, 9),
        endedAt: DateTime(2026, 8, 3, 9, 10),
        durationMinutes: 10,
        durationText: '00:10:00',
        bikeId: 'bike-fake-1',
        tripCost: '1.25',
      ),
    );

    expect(trip.originStationId, '34');
    expect(trip.destinationStationId, '164');
    expect(trip.bikeId, 'bike-fake-1');
    expect(trip.tripCost, '1.25');
  });
}
