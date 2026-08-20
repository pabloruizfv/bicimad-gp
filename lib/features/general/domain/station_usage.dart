import '../../stations/domain/station.dart';
import '../../stations/domain/station_catalog.dart';
import '../../trips/domain/trip.dart';

class StationUsage {
  const StationUsage({required this.station, required this.uses});

  final Station station;
  final int uses;
}

List<StationUsage> buildStationUsage({
  required List<Trip> trips,
  required StationCatalog catalog,
}) {
  final counts = <String, ({Station station, int uses})>{};
  for (final trip in trips) {
    _countStation(
      counts,
      catalog.resolve(
        stationId: trip.originStationId,
        stationName: trip.originStationName,
      ),
    );
    _countStation(
      counts,
      catalog.resolve(
        stationId: trip.destinationStationId,
        stationName: trip.destinationStationName,
      ),
    );
  }
  final usages = [
    for (final item in counts.values)
      StationUsage(station: item.station, uses: item.uses),
  ]..sort((a, b) => b.uses.compareTo(a.uses));
  return usages;
}

void _countStation(
  Map<String, ({Station station, int uses})> counts,
  Station? station,
) {
  if (station == null) {
    return;
  }
  final key = station.publicCode;
  final existing = counts[key];
  counts[key] = (
    station: station,
    uses: existing == null ? 1 : existing.uses + 1,
  );
}
