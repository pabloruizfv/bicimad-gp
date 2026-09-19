const String cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

abstract final class CartoBasemapConfig {
  static const String _rasterTileUrl =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

  static String get rasterTileUrlTemplate => buildRasterTileUrlTemplate();

  static String buildRasterTileUrlTemplate({String apiKey = cartoApiKey}) {
    return '$_rasterTileUrl?key=${Uri.encodeQueryComponent(apiKey)}';
  }

  static void ensureConfigured({String apiKey = cartoApiKey}) {
    if (apiKey.trim().isNotEmpty) {
      return;
    }
    throw StateError(
      'Falta CARTO_API_KEY. Ejecuta la aplicacion con: '
      'flutter run '
      '--dart-define-from-file=local_secrets.json',
    );
  }
}
