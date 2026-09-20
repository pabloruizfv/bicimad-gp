import '../../stations/domain/terrain_elevation_grid.dart';
import 'trip.dart';

class TripElevationProfile {
  const TripElevationProfile({
    required this.netMeters,
    required this.segmentNetMeters,
  });

  /// Destination minus origin. This is not accumulated climbing.
  final double? netMeters;
  final List<double?> segmentNetMeters;
}

class TripElevationCalculator {
  const TripElevationCalculator(this.grid);

  final TerrainElevationGrid grid;

  double? netMetersBetween({
    required double? originLatitude,
    required double? originLongitude,
    required double? destinationLatitude,
    required double? destinationLongitude,
  }) {
    final origin = _at(originLatitude, originLongitude);
    final destination = _at(destinationLatitude, destinationLongitude);
    return origin == null || destination == null ? null : destination - origin;
  }

  TripElevationProfile forTrip(Trip trip) {
    final elevations = <double?>[
      _at(trip.originLatitude, trip.originLongitude),
      for (final stop in trip.pitStops) _at(stop.latitude, stop.longitude),
      _at(trip.destinationLatitude, trip.destinationLongitude),
    ];
    final segments = <double?>[
      for (var i = 1; i < elevations.length; i++)
        elevations[i - 1] == null || elevations[i] == null
            ? null
            : elevations[i]! - elevations[i - 1]!,
    ];
    return TripElevationProfile(
      netMeters: elevations.first == null || elevations.last == null
          ? null
          : elevations.last! - elevations.first!,
      segmentNetMeters: List.unmodifiable(segments),
    );
  }

  double? _at(double? latitude, double? longitude) =>
      latitude == null || longitude == null
      ? null
      : grid.elevationAt(latitude: latitude, longitude: longitude);
}
