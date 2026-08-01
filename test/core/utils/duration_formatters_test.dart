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
}
