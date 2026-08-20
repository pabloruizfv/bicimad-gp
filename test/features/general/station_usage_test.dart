import 'package:bicimad_social/features/general/domain/station_usage.dart';
import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/stations/domain/station_catalog.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cuenta estaciones usando primero el codigo publico del nombre', () {
    final catalog = StationCatalog(
      stations: const [
        Station(
          id: 'colombia-id',
          publicCode: '99',
          name: 'Colombia',
          latitude: 40.45,
          longitude: -3.67,
        ),
        Station(
          id: 'real-id',
          publicCode: '34',
          name: 'Jacinto Benavente',
          latitude: 40.41,
          longitude: -3.70,
        ),
      ],
      updatedAt: DateTime(2026, 8, 3),
    );

    final usages = buildStationUsage(
      catalog: catalog,
      trips: [
        _trip(
          id: 'trip-1',
          originStationId: 'colombia-id',
          originStationName: '34 - Jacinto Benavente',
          destinationStationId: 'real-id',
          destinationStationName: '34 - Jacinto Benavente',
        ),
      ],
    );

    expect(usages, hasLength(1));
    expect(usages.single.station.name, 'Jacinto Benavente');
    expect(usages.single.uses, 2);
  });
}

Trip _trip({
  required String id,
  required String originStationId,
  required String originStationName,
  required String destinationStationId,
  required String destinationStationName,
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'current-user',
    originStationId: originStationId,
    originStationName: originStationName,
    destinationStationId: destinationStationId,
    destinationStationName: destinationStationName,
    startedAt: DateTime(2026, 8, 3, 9),
    durationSeconds: 600,
    isShared: true,
  );
}
