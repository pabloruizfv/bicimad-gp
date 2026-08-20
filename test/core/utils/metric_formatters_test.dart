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
}
