import '../../rankings/domain/ranking_service.dart';
import '../../rankings/domain/route_ranking.dart';
import '../domain/community_repository.dart';
import '../domain/community_user.dart';
import '../domain/journey_builder.dart';
import '../domain/trip.dart';
import '../domain/trip_history_sync.dart';
import '../domain/trip_metrics.dart';
import 'mock_bicimad_data.dart';

class MockCommunityRepository implements CommunityRepository {
  MockCommunityRepository({
    RankingService rankingService = const RankingService(),
  }) : this._(rankingService);

  MockCommunityRepository._(this._rankingService)
    : _users = [...mockCommunityUsers],
      _trips = [...mockTrips];

  final RankingService _rankingService;
  final JourneyBuilder _journeyBuilder = const JourneyBuilder();
  final List<Trip> _trips;
  List<CommunityUser> _users;
  String? _currentUserId;
  TripHistorySyncState _historySyncState = const TripHistorySyncState.initial();
  final Set<String> _knownSourceIds = {};

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
  Future<void> clear() async {
    _currentUserId = null;
  }

  @override
  Future<void> deleteMyData() async {
    final currentUserId = _currentUserId;
    if (currentUserId != null) {
      _trips.removeWhere((trip) => trip.userId == currentUserId);
      _knownSourceIds.clear();
      _historySyncState = const TripHistorySyncState.initial();
    }
    _currentUserId = null;
  }

  @override
  Future<List<Trip>> getMyTrips() async {
    final currentUserId = _requireCurrentUserId();
    final trips = _journeysForUser(currentUserId)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return trips;
  }

  @override
  Future<List<Trip>> getMyRankingTrips() async {
    return _rankingTripsForUser(_requireCurrentUserId());
  }

  @override
  Future<List<Trip>> getMyStages() async {
    final currentUserId = _requireCurrentUserId();
    return _trips
        .where(
          (trip) =>
              trip.userId == currentUserId &&
              trip.originStationId != trip.destinationStationId &&
              trip.durationSeconds > 0,
        )
        .toList(growable: false);
  }

  @override
  Future<List<CoverageInterval>> getCoverageIntervals() async {
    final trips = await getMyTrips();
    if (trips.isEmpty) {
      return const [];
    }
    final sorted = [...trips]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return [
      CoverageInterval(
        start: sorted.first.startedAt,
        end: sorted.last.startedAt,
      ),
    ];
  }

  @override
  Future<Set<String>> getKnownSourceTripIds() async {
    return {..._knownSourceIds};
  }

  @override
  Future<TripHistorySyncState> getTripHistorySyncState() async {
    return _historySyncState;
  }

  @override
  Future<List<Trip>> getTripsForRoute({
    required String originStationId,
    required String destinationStationId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _rankingTripsForUser(currentUserId)
        .where(
          (trip) =>
              trip.userId == currentUserId &&
              trip.matchesRoute(
                originStationId: originStationId,
                destinationStationId: destinationStationId,
              ),
        )
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  @override
  Future<RouteRanking> getRouteRanking({
    required String originStationId,
    required String destinationStationId,
  }) async {
    return _rankingService.buildRouteRanking(
      trips: _rankingTripsForUser(_requireCurrentUserId()),
      users: _users,
      currentUserId: _requireCurrentUserId(),
      originStationId: originStationId,
      destinationStationId: destinationStationId,
    );
  }

  @override
  Future<List<Trip>> getSharedTrips() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return const [];
    }
    return _rankingTripsForUser(
      currentUserId,
    ).where((trip) => trip.isShared).toList();
  }

  @override
  Future<void> replaceMyTrips(List<Trip> trips) async {
    final currentUserId = _requireCurrentUserId();
    _knownSourceIds.addAll(
      trips
          .where((trip) => trip.userId == currentUserId)
          .map((trip) => trip.externalId),
    );
    final byStableKey = <String, Trip>{
      for (final trip in _trips) _stableTripKey(trip): trip,
    };

    for (final trip in trips.where(
      (trip) =>
          trip.userId == currentUserId &&
          trip.originStationId != trip.destinationStationId &&
          trip.durationSeconds > 0,
    )) {
      final key = _stableTripKey(trip);
      final existing = byStableKey[key];
      byStableKey[key] = existing == null
          ? trip
          : trip.copyWith(
              bikeId: trip.bikeId ?? existing.bikeId,
              tripCost: trip.tripCost ?? existing.tripCost,
              originLatitude: trip.originLatitude ?? existing.originLatitude,
              originLongitude: trip.originLongitude ?? existing.originLongitude,
              destinationLatitude:
                  trip.destinationLatitude ?? existing.destinationLatitude,
              destinationLongitude:
                  trip.destinationLongitude ?? existing.destinationLongitude,
              directDistanceMeters:
                  trip.directDistanceMeters ?? existing.directDistanceMeters,
            );
    }

    _trips
      ..clear()
      ..addAll(byStableKey.values);
  }

  @override
  Future<void> upsertMyTripPage(List<Trip> trips) => replaceMyTrips(trips);

  @override
  Future<void> recordTripHistoryImport(TripHistoryImportRecord record) async {
    _historySyncState = record.state;
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

  String _stableTripKey(Trip trip) => '${trip.userId}:${trip.externalId}';

  List<Trip> _journeysForUser(String userId) {
    return _journeyBuilder.buildJourneys(
      _trips.where((trip) => trip.userId == userId),
    );
  }

  List<Trip> _rankingTripsForUser(String userId) {
    return _journeyBuilder.buildRankingTrips(
      _trips.where((trip) => trip.userId == userId),
    );
  }
}
