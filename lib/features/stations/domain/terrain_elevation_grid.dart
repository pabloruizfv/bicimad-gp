import 'dart:typed_data';

/// A north-up, regularly spaced WGS84 grid of terrain elevations.
class TerrainElevationGrid {
  TerrainElevationGrid({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.stepDegrees,
    required this.width,
    required this.height,
    required this.scaleMeters,
    required this.nodata,
    required Uint8List bytes,
  }) : _samples = ByteData.sublistView(bytes) {
    if (width < 1 || height < 1 || stepDegrees <= 0 || scaleMeters <= 0) {
      throw const FormatException('Invalid terrain grid dimensions.');
    }
    if (_samples.lengthInBytes != width * height * 2) {
      throw const FormatException('Invalid terrain grid length.');
    }
  }

  final double west;
  final double south;
  final double east;
  final double north;
  final double stepDegrees;
  final int width;
  final int height;
  final double scaleMeters;
  final int nodata;
  final ByteData _samples;

  double? elevationAt({required double latitude, required double longitude}) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        longitude < west ||
        longitude > east ||
        latitude < south ||
        latitude > north) {
      return null;
    }

    final x = ((longitude - west) / stepDegrees - 0.5).clamp(0.0, width - 1.0);
    final y = ((north - latitude) / stepDegrees - 0.5).clamp(0.0, height - 1.0);
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1 < width ? x0 + 1 : x0;
    final y1 = y0 + 1 < height ? y0 + 1 : y0;
    final dx = x - x0;
    final dy = y - y0;
    final samples = <(int, double)>[
      (_sample(x0, y0), (1 - dx) * (1 - dy)),
      (_sample(x1, y0), dx * (1 - dy)),
      (_sample(x0, y1), (1 - dx) * dy),
      (_sample(x1, y1), dx * dy),
    ];
    var total = 0.0;
    for (final (value, weight) in samples) {
      if (weight <= 1e-8) continue;
      if (value == nodata) return null;
      total += value * weight;
    }
    return total * scaleMeters;
  }

  int _sample(int x, int y) =>
      _samples.getInt16((y * width + x) * 2, Endian.little);
}
