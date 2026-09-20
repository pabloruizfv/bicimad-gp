class Station {
  const Station({
    required this.id,
    required this.publicCode,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.elevationMeters,
  });

  final String id;
  final String publicCode;
  final String name;
  final double latitude;
  final double longitude;
  final double? elevationMeters;

  Station withElevation(double? elevation) => Station(
    id: id,
    publicCode: publicCode,
    name: name,
    latitude: latitude,
    longitude: longitude,
    elevationMeters: elevation,
  );

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'public_code': publicCode,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      if (elevationMeters != null) 'elevation_meters': elevationMeters,
    };
  }

  static Station? fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String?)?.trim();
    final publicCode = (json['public_code'] as String?)?.trim();
    final name = (json['name'] as String?)?.trim();
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final elevation = json['elevation_meters'];
    if (id == null ||
        id.isEmpty ||
        publicCode == null ||
        publicCode.isEmpty ||
        name == null ||
        name.isEmpty ||
        latitude is! num ||
        longitude is! num) {
      return null;
    }
    return Station(
      id: id,
      publicCode: publicCode,
      name: name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      elevationMeters: elevation is num ? elevation.toDouble() : null,
    );
  }
}
