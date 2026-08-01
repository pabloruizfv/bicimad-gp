import '../../rankings/domain/route_ranking.dart';
import 'community_user.dart';
import 'trip.dart';

abstract interface class CommunityRepository {
  Future<CommunityUser> createOrRecoverUser({required String externalUserId});

  Future<void> updateDisplayName(String displayName);

  Future<List<Trip>> getMyTrips();

  Future<List<Trip>> getSharedTrips();

  Future<List<CommunityUser>> getCommunityUsers();

  Future<RouteRanking> getRouteRanking({
    required String originStationId,
    required String destinationStationId,
  });
}
