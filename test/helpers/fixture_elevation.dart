import 'dart:typed_data';

import 'package:bicimad_social/features/stations/domain/terrain_elevation_grid.dart';
import 'package:bicimad_social/features/trips/domain/trip_elevation.dart';

TripElevationCalculator fixtureElevationCalculator() {
  final bytes = Uint8List(8);
  final data = ByteData.sublistView(bytes);
  for (final (index, value) in [1000, 2000, 3000, 4000].indexed) {
    data.setInt16(index * 2, value, Endian.little);
  }
  return TripElevationCalculator(
    TerrainElevationGrid(
      west: -4,
      south: 39,
      east: -2,
      north: 41,
      stepDegrees: 1,
      width: 2,
      height: 2,
      scaleMeters: 0.1,
      nodata: -32768,
      bytes: bytes,
    ),
  );
}
