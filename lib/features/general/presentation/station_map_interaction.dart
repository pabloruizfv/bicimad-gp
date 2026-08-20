import 'dart:math' as math;
import 'dart:ui';

const double minimumStationMarkerDiameter = 12;
const double maximumStationMarkerDiameter = 42;
const double stationMarkerTouchDiameter = 52;
const double stationMapTapRadius = 30;

double stationMarkerDiameter({required int uses, required int maxUses}) {
  if (uses <= 0 || maxUses <= 0) {
    return minimumStationMarkerDiameter;
  }
  final ratio = (uses / maxUses).clamp(0.0, 1.0);
  return minimumStationMarkerDiameter +
      (maximumStationMarkerDiameter - minimumStationMarkerDiameter) *
          math.sqrt(ratio);
}

int? closestStationIndex({
  required Offset tapPosition,
  required List<Offset> stationPositions,
  double radius = stationMapTapRadius,
}) {
  var closestDistanceSquared = radius * radius;
  int? closestIndex;
  for (var index = 0; index < stationPositions.length; index++) {
    final delta = stationPositions[index] - tapPosition;
    final distanceSquared = delta.dx * delta.dx + delta.dy * delta.dy;
    if (distanceSquared <= closestDistanceSquared) {
      closestDistanceSquared = distanceSquared;
      closestIndex = index;
    }
  }
  return closestIndex;
}
