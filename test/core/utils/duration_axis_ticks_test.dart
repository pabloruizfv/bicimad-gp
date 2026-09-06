import 'package:bicimad_social/core/utils/duration_axis_ticks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'genera entre cuatro y seis marcas con intervalos temporales redondos',
    () {
      expect(durationAxisTicks(0, 1200), [0, 300, 600, 900, 1200]);
      expect(durationAxisTicks(37, 183), [60, 90, 120, 150, 180]);
      expect(durationAxisTicks(0, 220), [0, 60, 120, 180]);
    },
  );

  test('formatea marcas compactas de segundos, minutos y horas', () {
    expect(formatDurationAxisTick(0), '0 s');
    expect(formatDurationAxisTick(45), '45 s');
    expect(formatDurationAxisTick(300), '5 min');
    expect(formatDurationAxisTick(330), '5:30');
    expect(formatDurationAxisTick(5400), '1 h 30 min');
  });
}
