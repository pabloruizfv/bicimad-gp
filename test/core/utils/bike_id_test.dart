import 'package:bicimad_social/core/utils/bike_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('elimina ceros iniciales de identificadores numericos', () {
    expect(normalizeBikeId('00012345'), '12345');
    expect(normalizeBikeId('00000000'), '0');
    expect(normalizeBikeId(' 0012 '), '12');
  });

  test('conserva identificadores no numericos', () {
    expect(normalizeBikeId('bike-001'), 'bike-001');
    expect(normalizeBikeId(null), isNull);
  });
}
