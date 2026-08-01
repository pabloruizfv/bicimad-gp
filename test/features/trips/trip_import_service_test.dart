import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/domain/trip_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = TripImportService();

  test('prevents duplicates by userId and externalId', () {
    final existing = [_trip('local-1', 'external-1', 'user-a')];
    final imported = [
      _trip('local-duplicate', 'external-1', 'user-a'),
      _trip('local-2', 'external-1', 'user-b'),
      _trip('local-3', 'external-2', 'user-a'),
    ];

    final merged = service.mergeUniqueTrips(
      existingTrips: existing,
      importedTrips: imported,
    );

    expect(merged.map((trip) => trip.id), ['local-1', 'local-2', 'local-3']);
  });
}

Trip _trip(String id, String externalId, String userId) {
  return Trip(
    id: id,
    externalId: externalId,
    userId: userId,
    originStationId: 'MB',
    originStationName: 'Manuel Becerra',
    destinationStationId: 'FII',
    destinationStationName: 'Felipe II',
    startedAt: DateTime(2026, 7, 20, 8),
    durationSeconds: 420,
    isShared: true,
  );
}
