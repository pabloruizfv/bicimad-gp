import 'package:bicimad_social/core/utils/duration_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDurationSeconds', () {
    test('formats durations under one hour as minutes and seconds', () {
      expect(formatDurationSeconds(408), '6:48');
      expect(formatDurationSeconds(754), '12:34');
    });

    test('formats durations over one hour with hours', () {
      expect(formatDurationSeconds(3723), '1:02:03');
    });
  });

  group('formatCompactReadableDurationSeconds', () {
    test('limits hour durations to hours and minutes', () {
      expect(formatCompactReadableDurationSeconds(26783), "7h 26'");
    });

    test('keeps seconds for durations under one hour', () {
      expect(formatCompactReadableDurationSeconds(2090), "34' 50''");
    });
  });

  group('formatPrimeDurationSeconds', () {
    test('uses prime notation for minutes and seconds', () {
      expect(formatPrimeDurationSeconds(910), '15′ 10″');
    });

    test('keeps hours when needed', () {
      expect(formatPrimeDurationSeconds(3970), '1h 06′ 10″');
    });
  });
}
