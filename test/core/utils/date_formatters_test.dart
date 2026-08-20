import 'package:bicimad_social/core/utils/date_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatea fecha y hora con el dia de la semana', () {
    expect(
      formatWeekdayDateTime(DateTime(2026, 8, 3, 19, 23)),
      'Lunes 03/08/2026 19:23',
    );
  });
}
