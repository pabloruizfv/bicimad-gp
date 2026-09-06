import 'package:bicimad_social/core/config/carto_basemap_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartoBasemapConfig', () {
    test('adds an encoded key to the existing light raster style', () {
      final url = CartoBasemapConfig.buildRasterTileUrlTemplate(
        apiKey: 'test key',
      );

      expect(
        url,
        'https://{s}.basemaps.cartocdn.com/'
        'light_all/{z}/{x}/{y}{r}.png?key=test+key',
      );
    });

    test('fails clearly when configuration is empty', () {
      expect(
        () => CartoBasemapConfig.ensureConfigured(apiKey: ''),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('CARTO_API_KEY'),
              )
              .having(
                (error) => error.message,
                'run command',
                contains('--dart-define-from-file=local_secrets.json'),
              ),
        ),
      );
    });
  });
}
