import 'package:flutter_map/flutter_map.dart';

import '../../core/config/carto_basemap_config.dart';

class CartoTileLayer extends TileLayer {
  CartoTileLayer({super.key})
    : super(
        urlTemplate: CartoBasemapConfig.rasterTileUrlTemplate,
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: 'bicimad_social',
        // flutter_map's default error output includes the URL and its API key.
        tileProvider: NetworkTileProvider(silenceExceptions: true),
      );
}
