import 'package:flutter_test/flutter_test.dart';

import 'package:bicimad_social/features/app_update/domain/app_update.dart';

void main() {
  group('compareVersions', () {
    test('compares semantic numeric versions', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(compareVersions('2.0', '1.99.99'), greaterThan(0));
    });

    test('missing patch components are treated as zero', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
    });
  });
}
