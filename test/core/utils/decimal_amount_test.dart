import 'package:bicimad_social/core/utils/decimal_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza importes sin convertirlos a centimos', () {
    expect(normalizeDecimalAmount('1.2300'), '1.2300');
    expect(normalizeDecimalAmount('0,75'), '0.75');
    expect(normalizeDecimalAmount(null), isNull);
  });

  test('suma importes decimales exactamente y exige todos los valores', () {
    expect(sumDecimalAmounts(['0.10', '0.20', '1.005']), '1.305');
    expect(sumDecimalAmounts(['1.20', '2.3']), '3.50');
    expect(sumDecimalAmounts(['1.00', null]), isNull);
  });

  test('formatea el precio conservando su precision decimal', () {
    expect(formatDecimalEuros('1.2300'), '1,2300 €');
    expect(formatDecimalEuros(null), 'No disponible');
  });

  test('detecta importes estrictamente positivos', () {
    expect(isPositiveDecimalAmount('1.20'), isTrue);
    expect(isPositiveDecimalAmount('0.0'), isFalse);
    expect(isPositiveDecimalAmount('-1.0'), isFalse);
    expect(isPositiveDecimalAmount(null), isFalse);
  });
}
