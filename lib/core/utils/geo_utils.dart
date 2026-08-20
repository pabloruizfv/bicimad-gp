import 'dart:math' as math;

const _earthRadiusMeters = 6371000.0;

double haversineDistanceMeters({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  final fromLat = _radians(fromLatitude);
  final toLat = _radians(toLatitude);
  final deltaLat = _radians(toLatitude - fromLatitude);
  final deltaLon = _radians(toLongitude - fromLongitude);

  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLat) *
          math.cos(toLat) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

double _radians(double degrees) => degrees * math.pi / 180;
