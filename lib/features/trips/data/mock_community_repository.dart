import '../../rankings/domain/ranking_service.dart';
import '../../rankings/domain/route_ranking.dart';
import '../domain/community_repository.dart';
import '../domain/community_user.dart';
import '../domain/trip.dart';
import 'mock_bicimad_data.dart';

class MockCommunityRepository implements CommunityRepository {
  MockCommunityRepository({
    RankingService rankingService = const RankingService(),
  }) : this._(rankingService);

  MockCommunityRepository._(this._rankingService)
    : _users = [...mockCommunityUsers],
      _trips = [...mockTrips];

  final RankingService _rankingService;
  final List<Trip> _trips;
  List<CommunityUser> _users;
  String? _currentUserId;

  @override
  Future<CommunityUser> createOrRecoverUser({
    required String externalUserId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _currentUserId = mockCurrentUserId;
    return _currentUser;
  }

  @override
  Future<List<CommunityUser>> getCommunityUsers() async {
    return [..._users];
  }

  @override
  Future<List<Trip>> getMyTrips() async {
    final currentUserId = _requireCurrentUserId();
    final trips = _trips.where((trip) => trip.userId == currentUserId).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return trips;
  }

  @override
  Future<RouteRanking> getRouteRanking({
    required String originStationId,
    required String destinationStationId,
  }) async {
    return _rankingService.buildRouteRanking(
      trips: _trips,
      users: _users,
      currentUserId: _requireCurrentUserId(),
      originStationId: originStationId,
      destinationStationId: destinationStationId,
    );
  }

  @override
  Future<List<Trip>> getSharedTrips() async {
    return _trips.where((trip) => trip.isShared).toList();
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final currentUserId = _requireCurrentUserId();
    _users = [
      for (final user in _users)
        if (user.id == currentUserId)
          user.copyWith(displayName: displayName.trim())
        else
          user,
    ];
  }

  CommunityUser get _currentUser {
    final currentUserId = _requireCurrentUserId();
    return _users.firstWhere((user) => user.id == currentUserId);
  }

  String _requireCurrentUserId() {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw StateError('No hay usuario simulado activo.');
    }
    return currentUserId;
  }
}
