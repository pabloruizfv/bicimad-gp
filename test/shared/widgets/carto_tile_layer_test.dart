import 'package:bicimad_social/shared/widgets/carto_tile_layer.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps CARTO light tiles and suppresses URL-bearing network errors', () async {
    final layer = CartoTileLayer();
    final provider = layer.tileProvider as NetworkTileProvider;
    expect(layer.urlTemplate, contains('basemaps.cartocdn.com/light_all/'));
    expect(layer.urlTemplate, contains('?key='));
    expect(layer.subdomains, ['a', 'b', 'c', 'd']);
    expect(provider.silenceExceptions, isTrue);
    await provider.dispose();
  });
}
