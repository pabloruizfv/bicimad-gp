String formatDistanceMeters(double? meters) {
  if (meters == null) {
    return 'No disponible';
  }
  final roundedMeters = (meters / 10).round() * 10;
  if (roundedMeters < 1000) {
    return '$roundedMeters m';
  }
  return '${(roundedMeters / 1000).toStringAsFixed(2)} km';
}

/// Signed destination-minus-origin elevation, not accumulated climbing.
String? formatElevationDifferenceMeters(double? meters) {
  if (meters == null || !meters.isFinite) return null;
  final rounded = meters.round();
  return '${rounded > 0 ? '+' : ''}$rounded m';
}

String formatDistanceWithElevation(double? distanceMeters, double? netMeters) {
  final distance = formatDistanceMeters(distanceMeters);
  final elevation = formatElevationDifferenceMeters(netMeters);
  return elevation == null ? distance : '$distance · $elevation';
}

String formatSpeedKmh(double? kmh) {
  if (kmh == null) {
    return 'No disponible';
  }
  return '${kmh.toStringAsFixed(1)} km/h';
}
