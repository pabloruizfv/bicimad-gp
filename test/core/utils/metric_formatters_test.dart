import 'package:bicimad_social/core/utils/metric_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redondea distancias al multiplo de diez metros mas cercano', () {
    expect(formatDistanceMeters(841), '840 m');
    expect(formatDistanceMeters(846), '850 m');
    expect(formatDistanceMeters(1254), '1.25 km');
    expect(formatDistanceMeters(1256), '1.26 km');
  });

  test('mantiene el estado no disponible', () {
    expect(formatDistanceMeters(null), 'No disponible');
  });

  test('formatea el desnivel neto con signo y omite el desconocido', () {
    expect(formatDistanceWithElevation(841, 24.6), '840 m · +25 m');
    expect(formatDistanceWithElevation(841, -24.6), '840 m · -25 m');
    expect(formatDistanceWithElevation(841, 0), '840 m · 0 m');
    expect(formatDistanceWithElevation(841, null), '840 m');
  });
}
