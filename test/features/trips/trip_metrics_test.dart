import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/stations/domain/station_catalog.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/domain/trip_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enriquece viaje con coordenadas y distancia Haversine', () {
    final catalog = StationCatalog(
      stations: const [
        Station(
          id: 'A',
          publicCode: '1',
          name: 'Origen',
          latitude: 40.4168,
          longitude: -3.7038,
        ),
        Station(
          id: 'B',
          publicCode: '2',
          name: 'Destino',
          latitude: 40.4210,
          longitude: -3.7050,
        ),
      ],
      updatedAt: DateTime(2026, 8, 2),
    );

    final enriched = const TripMetricsEnricher().enrich(_trip('t1'), catalog);

    expect(enriched.originLatitude, 40.4168);
    expect(enriched.destinationLongitude, -3.7050);
    expect(enriched.directDistanceMeters, isNotNull);
    expect(enriched.directDistanceMeters!, greaterThan(400));
    expect(enriched.equivalentAverageSpeedKmh, isNotNull);
  });

  test('deja metrica no disponible si una estacion no se resuelve', () {
    final catalog = StationCatalog(
      stations: const [
        Station(
          id: 'A',
          publicCode: '1',
          name: 'Origen',
          latitude: 40.4168,
          longitude: -3.7038,
        ),
      ],
      updatedAt: DateTime(2026, 8, 2),
    );

    final enriched = const TripMetricsEnricher().enrich(_trip('t1'), catalog);

    expect(enriched.directDistanceMeters, isNull);
    expect(enriched.equivalentAverageSpeedKmh, isNull);
  });

  test('metricas generales distinguen dias de viajes e historial cubierto', () {
    final metrics = GeneralTripMetrics.fromTrips(
      trips: [
        _trip('t1', startedAt: DateTime(2026, 8, 1, 10), distance: 1000),
        _trip('t2', startedAt: DateTime(2026, 8, 1, 12), distance: 2000),
        _trip('t3', startedAt: DateTime(2026, 8, 5, 12)),
      ],
      coverageIntervals: [
        CoverageInterval(
          start: DateTime(2026, 8, 1, 10),
          end: DateTime(2026, 8, 2, 10),
        ),
        CoverageInterval(
          start: DateTime(2026, 8, 5, 10),
          end: DateTime(2026, 8, 5, 12),
        ),
      ],
    );

    expect(metrics.totalTrips, 3);
    expect(metrics.distinctTripDays, 2);
    expect(metrics.historySpanDays, 5);
    expect(metrics.totalDirectDistanceMeters, 3000);
    expect(metrics.tripsWithDistance, 2);
    expect(metrics.coverageDays, 3);
    expect(metrics.periodCount, 2);
  });

  test('fusiona cobertura solo cuando hay IDs ya conocidos', () {
    final oldTrip = _trip('old', startedAt: DateTime(2026, 8, 1));
    final repeatedOld = _trip('old', startedAt: DateTime(2026, 8, 1));
    final newTrip = _trip('new', startedAt: DateTime(2026, 8, 3));
    final unrelated = _trip('other', startedAt: DateTime(2026, 8, 2));

    final merged = mergeCoverageForImport(
      existing: [
        CoverageInterval(start: oldTrip.startedAt, end: oldTrip.startedAt),
      ],
      importedTrips: [repeatedOld, newTrip],
      knownTripKeysBeforeImport: {'user-1:old'},
    );
    final notMerged = mergeCoverageForImport(
      existing: [
        CoverageInterval(start: oldTrip.startedAt, end: oldTrip.startedAt),
      ],
      importedTrips: [unrelated],
      knownTripKeysBeforeImport: {'user-1:old'},
    );

    expect(merged, hasLength(1));
    expect(merged.first.end, DateTime(2026, 8, 3));
    expect(notMerged, hasLength(2));
  });
}

Trip _trip(String id, {DateTime? startedAt, double? distance}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user-1',
    originStationId: 'A',
    originStationName: 'Origen',
    destinationStationId: 'B',
    destinationStationName: 'Destino',
    startedAt: startedAt ?? DateTime(2026, 8, 2, 10),
    durationSeconds: 600,
    isShared: true,
    directDistanceMeters: distance,
  );
}
