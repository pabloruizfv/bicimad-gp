import 'package:bicimad_social/features/general/presentation/station_map_interaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa escala de raiz cuadrada entre 12 y 42 px', () {
    expect(
      stationMarkerDiameter(uses: 1, maxUses: 100),
      inInclusiveRange(12, 42),
    );
    expect(stationMarkerDiameter(uses: 25, maxUses: 100), 27);
    expect(stationMarkerDiameter(uses: 100, maxUses: 100), 42);
    expect(stationMarkerTouchDiameter, 52);
  });

  test('selecciona un marcador pequeno con una pulsacion cercana', () {
    final selected = closestStationIndex(
      tapPosition: const Offset(124, 100),
      stationPositions: const [Offset(100, 100)],
    );

    expect(selected, 0);
  });

  test('entre estaciones solapadas selecciona la realmente mas proxima', () {
    final selected = closestStationIndex(
      tapPosition: const Offset(117, 102),
      stationPositions: const [Offset(100, 100), Offset(120, 100)],
    );

    expect(selected, 1);
  });

  test('no selecciona estaciones fuera del radio tactil', () {
    final selected = closestStationIndex(
      tapPosition: const Offset(140, 100),
      stationPositions: const [Offset(100, 100)],
    );

    expect(selected, isNull);
  });
}
