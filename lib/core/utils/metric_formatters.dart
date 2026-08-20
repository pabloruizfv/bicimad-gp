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

String formatSpeedKmh(double? kmh) {
  if (kmh == null) {
    return 'No disponible';
  }
  return '${kmh.toStringAsFixed(1)} km/h';
}
