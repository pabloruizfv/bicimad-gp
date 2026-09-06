import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/domain/trip_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconoce las ubicaciones descartadas con variantes de formato', () {
    expect(isDiscardedBicimadStationName('Bici mal anclada'), isTrue);
    expect(isDiscardedBicimadStationName('0 - BICI MAL ANCLADA'), isTrue);
    expect(isDiscardedBicimadStationName('Ubicación no permitida'), isTrue);
    expect(isDiscardedBicimadStationName('Ubicacion   no permitida'), isTrue);
    expect(isDiscardedBicimadStationName('320 - Metro Lago'), isFalse);
  });

  test('descarta el viaje si cualquiera de los dos extremos es invalido', () {
    expect(
      isCountableBicimadStage(
        _trip(originName: 'Bici mal anclada', destinationName: '2 - Destino'),
      ),
      isFalse,
    );
    expect(
      isCountableBicimadStage(
        _trip(
          originName: '1 - Origen',
          destinationName: 'Ubicación no permitida',
        ),
      ),
      isFalse,
    );
    expect(isCountableBicimadStage(_trip()), isTrue);
  });
}

Trip _trip({
  String originName = '1 - Origen',
  String destinationName = '2 - Destino',
}) {
  return Trip(
    id: 'trip-1',
    externalId: 'trip-1',
    userId: 'user-1',
    originStationId: '1',
    originStationName: originName,
    destinationStationId: '2',
    destinationStationName: destinationName,
    startedAt: DateTime(2026, 8, 1),
    durationSeconds: 600,
    isShared: true,
  );
}
