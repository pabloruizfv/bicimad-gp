import 'trip.dart';

class TripImportService {
  const TripImportService();

  List<Trip> mergeUniqueTrips({
    required Iterable<Trip> existingTrips,
    required Iterable<Trip> importedTrips,
  }) {
    final result = <Trip>[...existingTrips];
    final seenKeys = {
      for (final trip in existingTrips)
        _TripImportKey(trip.userId, trip.externalId),
    };

    for (final trip in importedTrips) {
      final key = _TripImportKey(trip.userId, trip.externalId);
      if (seenKeys.add(key)) {
        result.add(trip);
      }
    }

    return result;
  }
}

class _TripImportKey {
  const _TripImportKey(this.userId, this.externalId);

  final String userId;
  final String externalId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _TripImportKey &&
            userId == other.userId &&
            externalId == other.externalId;
  }

  @override
  int get hashCode => Object.hash(userId, externalId);
}
