import '../../rankings/domain/route_ranking.dart';
import 'community_user.dart';
import 'trip.dart';
import 'trip_history_sync.dart';
import 'trip_metrics.dart';

abstract interface class CommunityRepository {
  Future<CommunityUser> createOrRecoverUser({required String externalUserId});

  Future<void> updateDisplayName(String displayName);

  Future<void> replaceMyTrips(List<Trip> trips);

  Future<void> upsertMyTripPage(List<Trip> trips);

  Future<Set<String>> getKnownSourceTripIds();

  Future<TripHistorySyncState> getTripHistorySyncState();

  Future<void> recordTripHistoryImport(TripHistoryImportRecord record);

  Future<List<Trip>> getMyTrips();

  Future<List<Trip>> getMyRankingTrips();

  Future<List<Trip>> getMyStages();

  Future<List<CoverageInterval>> getCoverageIntervals();

  Future<List<Trip>> getTripsForRoute({
    required String originStationId,
    required String destinationStationId,
  });

  Future<List<Trip>> getSharedTrips();

  Future<List<CommunityUser>> getCommunityUsers();

  Future<RouteRanking> getRouteRanking({
    required String originStationId,
    required String destinationStationId,
  });

  Future<void> clear();

  Future<void> deleteMyData();
}
