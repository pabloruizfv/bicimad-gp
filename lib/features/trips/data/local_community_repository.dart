import 'dart:convert';

import '../../../core/storage/secure_key_value_store.dart';
import '../../rankings/domain/ranking_service.dart';
import '../../rankings/domain/route_ranking.dart';
import '../../stations/data/station_catalog_repository.dart';
import '../../stations/domain/station_catalog.dart';
import '../domain/community_repository.dart';
import '../domain/community_user.dart';
import '../domain/journey_builder.dart';
import '../domain/trip.dart';
import '../domain/trip_history_sync.dart';
import '../domain/trip_metrics.dart';
import 'personal_trips_database.dart';

class LocalCommunityRepository implements CommunityRepository {
  LocalCommunityRepository({
    this.rankingService = const RankingService(),
    this.store,
    PersonalTripsDatabase? database,
    this.stationCatalogRepository,
    this.tripMetricsEnricher = const TripMetricsEnricher(),
    this.journeyBuilder = const JourneyBuilder(),
  }) : database =
           database ??
           (store == null
               ? PersonalTripsDatabase.inMemory()
               : _databaseForStore(store));

  static const _coverageStorageKey = 'community.coverageIntervals.v1';
  static const _historySyncStorageKey = 'community.tripHistorySync.v1';
  static final Expando<PersonalTripsDatabase> _testDatabases =
      Expando<PersonalTripsDatabase>();

  static PersonalTripsDatabase _databaseForStore(SecureKeyValueStore store) {
    return _testDatabases[store] ??= PersonalTripsDatabase.inMemory();
  }

  final RankingService rankingService;
  final SecureKeyValueStore? store;
  final PersonalTripsDatabase database;
  final StationCatalogRepository? stationCatalogRepository;
  final TripMetricsEnricher tripMetricsEnricher;
  final JourneyBuilder journeyBuilder;

  CommunityUser? _currentUser;
  List<CoverageInterval> _coverageIntervals = const [];
  TripHistorySyncState _historySyncState = const TripHistorySyncState.initial();
  String? _historySyncUserId;
  Future<void>? _initialization;
  String? _cacheUserId;
  List<Trip>? _stageCache;
  List<Trip>? _journeyCache;
  List<Trip>? _rankingTripCache;

  @override
  Future<void> clear() async {
    _currentUser = null;
    _invalidateTripCaches();
  }

  @override
  Future<void> deleteMyData() async {
    await _initialize();
    final user = _requireCurrentUser();
    await database.deleteUserData(user.id);
    final keyValueStore = store;
    if (keyValueStore != null) {
      await keyValueStore.delete(_coverageStorageKey);
      await keyValueStore.delete(_historySyncStorageKey);
      await keyValueStore.delete(PersonalTripsDatabase.legacyTripsStorageKey);
      await keyValueStore.delete(
        PersonalTripsDatabase.legacyKnownIdsStorageKey,
      );
    }
    _coverageIntervals = const [];
    _historySyncState = const TripHistorySyncState.initial();
    _historySyncUserId = null;
    _currentUser = null;
    _invalidateTripCaches();
  }

  @override
  Future<CommunityUser> createOrRecoverUser({
    required String externalUserId,
  }) async {
    await _initialize();
    final existing = _currentUser;
    if (existing != null && existing.externalUserId == externalUserId) {
      return existing;
    }
    if (_cacheUserId != externalUserId) {
      _invalidateTripCaches();
    }
    final user = CommunityUser(
      id: externalUserId,
      externalUserId: externalUserId,
      displayName: 'Usuario',
      createdAt: DateTime.now(),
    );
    _currentUser = user;
    return user;
  }

  @override
  Future<List<CommunityUser>> getCommunityUsers() async {
    return [_requireCurrentUser()];
  }

  @override
  Future<List<Trip>> getMyTrips() async {
    await _initialize();
    final user = _requireCurrentUser();
    return List.unmodifiable(await _journeysForUser(user.id));
  }

  @override
  Future<List<Trip>> getMyRankingTrips() async {
    await _initialize();
    final user = _requireCurrentUser();
    return List.unmodifiable(await _rankingTripsForUser(user.id));
  }

  @override
  Future<List<Trip>> getMyStages() async {
    await _initialize();
    final user = _currentUser;
    if (user == null) {
      return const [];
    }
    return List.unmodifiable(await _stagesForUser(user.id));
  }

  @override
  Future<List<CoverageInterval>> getCoverageIntervals() async {
    await _initialize();
    return [..._coverageIntervals]..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<Set<String>> getKnownSourceTripIds() async {
    await _initialize();
    return database.getKnownSourceIds(_requireCurrentUser().id);
  }

  @override
  Future<TripHistorySyncState> getTripHistorySyncState() async {
    await _initialize();
    final user = _requireCurrentUser();
    return _historySyncUserId == user.id
        ? _historySyncState
        : const TripHistorySyncState.initial();
  }

  @override
  Future<List<Trip>> getTripsForRoute({
    required String originStationId,
    required String destinationStationId,
  }) async {
    await _initialize();
    final rankingTrips = await _rankingTripsForUser(_requireCurrentUser().id);
    return rankingTrips
        .where(
          (trip) => trip.matchesRoute(
            originStationId: originStationId,
            destinationStationId: destinationStationId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RouteRanking> getRouteRanking({
    required String originStationId,
    required String destinationStationId,
  }) async {
    await _initialize();
    final user = _requireCurrentUser();
    return rankingService.buildRouteRanking(
      trips: await _rankingTripsForUser(user.id),
      users: [user],
      currentUserId: user.id,
      originStationId: originStationId,
      destinationStationId: destinationStationId,
    );
  }

  @override
  Future<List<Trip>> getSharedTrips() async {
    await _initialize();
    final user = _currentUser;
    if (user == null) {
      return const [];
    }
    return (await _rankingTripsForUser(
      user.id,
    )).where((trip) => trip.isShared).toList(growable: false);
  }

  @override
  Future<void> replaceMyTrips(List<Trip> trips) {
    return _upsertTrips(trips, updateCoverage: true);
  }

  @override
  Future<void> upsertMyTripPage(List<Trip> trips) {
    return _upsertTrips(trips, updateCoverage: false);
  }

  @override
  Future<void> recordTripHistoryImport(TripHistoryImportRecord record) async {
    await _initialize();
    final user = _requireCurrentUser();
    final start = record.oldestImportedAt;
    final end = record.newestImportedAt;
    if (start != null && end != null) {
      _coverageIntervals = mergeCoverageForRange(
        existing: _coverageIntervals,
        importedStart: start,
        importedEnd: end,
        overlapsKnownTrips: record.overlapsKnownTrips,
      );
    }
    _historySyncState = record.state;
    _historySyncUserId = user.id;
    await _persistMetadata();
  }

  Future<void> _upsertTrips(
    List<Trip> trips, {
    required bool updateCoverage,
  }) async {
    await _initialize();
    final user = _requireCurrentUser();
    final userTrips = trips
        .where((trip) => trip.userId == user.id)
        .toList(growable: false);
    if (userTrips.isEmpty) {
      return;
    }

    final knownKeys = updateCoverage
        ? {
            for (final trip in await _stagesForUser(user.id))
              _stableTripKey(trip),
          }
        : const <String>{};
    await database.upsertKnownSourceIds(
      user.id,
      userTrips.map((trip) => trip.externalId),
    );
    final incomingStages = userTrips
        .where(_isCountableStage)
        .toList(growable: false);
    final enrichedIncoming = await _enrichTripsIfPossible(incomingStages);
    await database.upsertTrips(enrichedIncoming);
    _invalidateTripCaches(user.id);

    if (updateCoverage) {
      _coverageIntervals = mergeCoverageForImport(
        existing: _coverageIntervals,
        importedTrips: enrichedIncoming,
        knownTripKeysBeforeImport: knownKeys,
      );
      await _persistMetadata();
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final user = _requireCurrentUser();
    _currentUser = user.copyWith(displayName: displayName.trim());
  }

  Future<void> _initialize() async {
    return _initialization ??= _initializeStorage();
  }

  Future<void> _initializeStorage() async {
    await database.migrateLegacyTrips(store);
    await _loadCoverageIntervals();
    await _loadTripHistorySyncState();
  }

  Future<List<Trip>> _stagesForUser(String userId) async {
    if (_cacheUserId == userId && _stageCache != null) {
      return _stageCache!;
    }
    var stages = await database.getTripsForUser(userId);
    final incomplete = stages.where(_needsMetricEnrichment).toList();
    if (incomplete.isNotEmpty) {
      final enriched = await _enrichTripsIfPossible(incomplete);
      await database.upsertTrips(enriched);
      final enrichedById = {for (final trip in enriched) trip.externalId: trip};
      stages = [
        for (final stage in stages) enrichedById[stage.externalId] ?? stage,
      ];
    }
    stages.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _cacheUserId = userId;
    _stageCache = List.unmodifiable(stages);
    _journeyCache = null;
    _rankingTripCache = null;
    return _stageCache!;
  }

  Future<List<Trip>> _journeysForUser(String userId) async {
    if (_cacheUserId == userId && _journeyCache != null) {
      return _journeyCache!;
    }
    final stages = await _stagesForUser(userId);
    final journeys = await _enrichTripsIfPossible(
      journeyBuilder.buildJourneys(stages),
    );
    journeys.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _journeyCache = List.unmodifiable(journeys);
    return _journeyCache!;
  }

  Future<List<Trip>> _rankingTripsForUser(String userId) async {
    if (_cacheUserId == userId && _rankingTripCache != null) {
      return _rankingTripCache!;
    }
    final stages = await _stagesForUser(userId);
    final rankingTrips = await _enrichTripsIfPossible(
      journeyBuilder.buildRankingTrips(stages),
    );
    rankingTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _rankingTripCache = List.unmodifiable(rankingTrips);
    return _rankingTripCache!;
  }

  Future<List<Trip>> _enrichTripsIfPossible(
    List<Trip> trips, {
    bool allowUnknownRefresh = true,
  }) async {
    final repository = stationCatalogRepository;
    if (repository == null || trips.isEmpty) {
      return trips;
    }
    final catalog = await repository.getCatalog();
    final enriched = <Trip>[];
    final unknownStations = <String, ({String id, String name})>{};
    for (final trip in trips) {
      final enrichedTrip = _enrichPitStops(
        tripMetricsEnricher.enrich(trip, catalog),
        catalog,
      );
      enriched.add(enrichedTrip);
      if (enrichedTrip.originLatitude == null ||
          enrichedTrip.originLongitude == null) {
        unknownStations['${trip.originStationId}|${trip.originStationName}'] = (
          id: trip.originStationId,
          name: trip.originStationName,
        );
      }
      if (enrichedTrip.destinationLatitude == null ||
          enrichedTrip.destinationLongitude == null) {
        unknownStations['${trip.destinationStationId}|${trip.destinationStationName}'] =
            (id: trip.destinationStationId, name: trip.destinationStationName);
      }
      for (final pitStop in enrichedTrip.pitStops) {
        if (pitStop.latitude == null || pitStop.longitude == null) {
          unknownStations['${pitStop.stationId}|${pitStop.stationName}'] = (
            id: pitStop.stationId,
            name: pitStop.stationName,
          );
        }
      }
    }
    if (unknownStations.isNotEmpty && allowUnknownRefresh) {
      for (final station in unknownStations.values) {
        await repository.refreshIfUnknown(
          stationId: station.id,
          stationName: station.name,
        );
      }
      return _enrichTripsIfPossible(trips, allowUnknownRefresh: false);
    }
    return enriched;
  }

  Trip _enrichPitStops(Trip trip, StationCatalog catalog) {
    if (trip.pitStops.isEmpty) {
      return trip;
    }
    return trip.copyWith(
      pitStops: [
        for (final pitStop in trip.pitStops)
          () {
            if (pitStop.latitude != null && pitStop.longitude != null) {
              return pitStop;
            }
            final station = catalog.resolve(
              stationId: pitStop.stationId,
              stationName: pitStop.stationName,
            );
            return station == null
                ? pitStop
                : pitStop.copyWith(
                    latitude: station.latitude,
                    longitude: station.longitude,
                  );
          }(),
      ],
    );
  }

  bool _needsMetricEnrichment(Trip trip) {
    return trip.originLatitude == null ||
        trip.originLongitude == null ||
        trip.destinationLatitude == null ||
        trip.destinationLongitude == null ||
        trip.directDistanceMeters == null ||
        trip.pitStops.any(
          (pitStop) => pitStop.latitude == null || pitStop.longitude == null,
        );
  }

  void _invalidateTripCaches([String? userId]) {
    _cacheUserId = userId;
    _stageCache = null;
    _journeyCache = null;
    _rankingTripCache = null;
  }

  Future<void> _loadCoverageIntervals() async {
    final keyValueStore = store;
    if (keyValueStore == null) {
      return;
    }
    final raw = await keyValueStore.read(_coverageStorageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return;
    }
    _coverageIntervals = [
      for (final item in decoded)
        if (item is Map)
          ?CoverageInterval.fromJson(Map<String, Object?>.from(item)),
    ].whereType<CoverageInterval>().toList(growable: false);
  }

  Future<void> _loadTripHistorySyncState() async {
    final keyValueStore = store;
    if (keyValueStore == null) {
      return;
    }
    final raw = await keyValueStore.read(_historySyncStorageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['state'] is Map) {
      _historySyncUserId = decoded['userId']?.toString();
      _historySyncState = TripHistorySyncState.fromJson(
        Map<String, Object?>.from(decoded['state'] as Map),
      );
    }
  }

  Future<void> _persistMetadata() async {
    final keyValueStore = store;
    if (keyValueStore == null) {
      return;
    }
    await keyValueStore.write(
      key: _coverageStorageKey,
      value: jsonEncode([
        for (final interval in _coverageIntervals) interval.toJson(),
      ]),
    );
    await keyValueStore.write(
      key: _historySyncStorageKey,
      value: jsonEncode({
        'userId': _historySyncUserId,
        'state': _historySyncState.toJson(),
      }),
    );
  }

  CommunityUser _requireCurrentUser() {
    final user = _currentUser;
    if (user == null) {
      throw StateError('No hay usuario activo.');
    }
    return user;
  }

  String _stableTripKey(Trip trip) => '${trip.userId}:${trip.externalId}';

  bool _isCountableStage(Trip trip) {
    return trip.originStationId != trip.destinationStationId &&
        trip.durationSeconds > 0;
  }
}
