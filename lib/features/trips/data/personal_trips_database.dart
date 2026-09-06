import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/storage/secure_key_value_store.dart';
import '../../../core/utils/bike_id.dart';
import '../domain/trip.dart';
import '../domain/trip_eligibility.dart';

class PersonalTripsDatabase {
  PersonalTripsDatabase._(this._databaseFuture);

  factory PersonalTripsDatabase.application() {
    return PersonalTripsDatabase._(_openApplicationDatabase());
  }

  factory PersonalTripsDatabase.inMemory() {
    return PersonalTripsDatabase._(Future.value(sqlite3.openInMemory()));
  }

  static const legacyTripsStorageKey = 'community.localTrips.v1';
  static const legacyKnownIdsStorageKey = 'community.knownSourceTripIds.v1';
  static const _legacyMigrationKey = 'legacy_secure_trips_v1';
  static const _discardedStationTripsMigrationKey =
      'discarded_station_trips_v1';

  final Future<Database> _databaseFuture;
  Future<void>? _initialization;

  static Future<Database> _openApplicationDatabase() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final path =
        '${directory.path}${Platform.pathSeparator}personal_trips.sqlite';
    return sqlite3.open(path);
  }

  Future<void> initialize() async {
    return _initialization ??= _initializeSchema();
  }

  Future<void> _initializeSchema() async {
    final database = await _databaseFuture;
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('''
      CREATE TABLE IF NOT EXISTS personal_trips (
        user_id TEXT NOT NULL,
        external_id TEXT NOT NULL,
        id TEXT NOT NULL,
        origin_station_id TEXT NOT NULL,
        origin_station_name TEXT NOT NULL,
        destination_station_id TEXT NOT NULL,
        destination_station_name TEXT NOT NULL,
        started_at_ms INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        is_shared INTEGER NOT NULL,
        origin_latitude REAL,
        origin_longitude REAL,
        destination_latitude REAL,
        destination_longitude REAL,
        direct_distance_meters REAL,
        bike_id TEXT,
        trip_cost TEXT,
        pit_stops_json TEXT NOT NULL DEFAULT '[]',
        stage_ids_json TEXT NOT NULL DEFAULT '[]',
        stage_details_json TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY (user_id, external_id)
      )
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS idx_personal_trips_user_started
      ON personal_trips(user_id, started_at_ms DESC)
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS idx_personal_trips_user_route_started
      ON personal_trips(
        user_id,
        origin_station_id,
        destination_station_id,
        started_at_ms DESC
      )
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS idx_personal_trips_user_bike
      ON personal_trips(user_id, bike_id)
      WHERE bike_id IS NOT NULL
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS known_source_trip_ids (
        user_id TEXT NOT NULL,
        external_id TEXT NOT NULL,
        PRIMARY KEY (user_id, external_id)
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _purgeDiscardedStationTrips(database);
  }

  Future<void> migrateLegacyTrips(SecureKeyValueStore? store) async {
    await initialize();
    if (store == null) {
      return;
    }
    final database = await _databaseFuture;
    if (_metadataValue(database, _legacyMigrationKey) == 'completed') {
      await _deleteLegacyBestEffort(store);
      return;
    }

    final rawTrips = await store.read(legacyTripsStorageKey);
    final rawKnownIds = await store.read(legacyKnownIdsStorageKey);
    final legacyTrips = _decodeLegacyTrips(rawTrips);
    final legacyKnownIds = _decodeLegacyKnownIds(rawKnownIds);
    final expected = <String, Set<String>>{};
    for (final trip in legacyTrips) {
      expected.putIfAbsent(trip.userId, () => <String>{}).add(trip.externalId);
    }
    for (final entry in legacyKnownIds.entries) {
      expected.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
    }

    database.execute('BEGIN IMMEDIATE');
    try {
      _upsertTripsSync(database, legacyTrips);
      _upsertKnownIdsSync(database, legacyKnownIds);
      for (final trip in legacyTrips) {
        _upsertKnownIdSync(database, trip.userId, trip.externalId);
      }
      if (!_containsExpectedIds(database, expected)) {
        throw StateError('La migracion local de viajes no se pudo verificar.');
      }
      database.execute(
        'INSERT OR REPLACE INTO app_metadata(key, value) VALUES (?, ?)',
        [_legacyMigrationKey, 'completed'],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }

    await _deleteLegacyBestEffort(store);
  }

  Future<void> upsertTrips(List<Trip> trips) async {
    if (trips.isEmpty) {
      return;
    }
    await initialize();
    final database = await _databaseFuture;
    database.execute('BEGIN IMMEDIATE');
    try {
      _upsertTripsSync(database, trips);
      for (final trip in trips) {
        _upsertKnownIdSync(database, trip.userId, trip.externalId);
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> upsertKnownSourceIds(
    String userId,
    Iterable<String> externalIds,
  ) async {
    await initialize();
    final database = await _databaseFuture;
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final externalId in externalIds) {
        _upsertKnownIdSync(database, userId, externalId);
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Trip>> getTripsForUser(
    String userId, {
    int? limit,
    int offset = 0,
  }) async {
    await initialize();
    final database = await _databaseFuture;
    final limitClause = limit == null ? '' : ' LIMIT ? OFFSET ?';
    final parameters = <Object?>[userId];
    if (limit != null) {
      parameters.addAll([limit, offset]);
    }
    final rows = database.select('''
      SELECT * FROM personal_trips
      WHERE user_id = ?
      ORDER BY started_at_ms DESC$limitClause
      ''', parameters);
    return [for (final row in rows) _tripFromRow(row)];
  }

  Future<List<Trip>> getTripsForRoute({
    required String userId,
    required String originStationId,
    required String destinationStationId,
    int? limit,
    int offset = 0,
  }) async {
    await initialize();
    final database = await _databaseFuture;
    final limitClause = limit == null ? '' : ' LIMIT ? OFFSET ?';
    final parameters = <Object?>[userId, originStationId, destinationStationId];
    if (limit != null) {
      parameters.addAll([limit, offset]);
    }
    final rows = database.select('''
      SELECT * FROM personal_trips
      WHERE user_id = ?
        AND origin_station_id = ?
        AND destination_station_id = ?
      ORDER BY started_at_ms DESC$limitClause
      ''', parameters);
    return [for (final row in rows) _tripFromRow(row)];
  }

  Future<Set<String>> getKnownSourceIds(String userId) async {
    await initialize();
    final database = await _databaseFuture;
    final rows = database.select(
      'SELECT external_id FROM known_source_trip_ids WHERE user_id = ?',
      [userId],
    );
    return {for (final row in rows) row['external_id'] as String};
  }

  Future<int> countTrips(String userId) async {
    await initialize();
    final database = await _databaseFuture;
    return database.select(
          'SELECT COUNT(*) AS count FROM personal_trips WHERE user_id = ?',
          [userId],
        ).single['count']
        as int;
  }

  Future<void> deleteUserData(String userId) async {
    await initialize();
    final database = await _databaseFuture;
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute('DELETE FROM personal_trips WHERE user_id = ?', [
        userId,
      ]);
      database.execute('DELETE FROM known_source_trip_ids WHERE user_id = ?', [
        userId,
      ]);
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> close() async {
    final database = await _databaseFuture;
    database.close();
  }

  static void _upsertTripsSync(Database database, Iterable<Trip> trips) {
    for (final trip in trips) {
      if (!isCountableBicimadStage(trip)) {
        continue;
      }
      database.execute('''
        INSERT INTO personal_trips (
          user_id, external_id, id,
          origin_station_id, origin_station_name,
          destination_station_id, destination_station_name,
          started_at_ms, duration_seconds, is_shared,
          origin_latitude, origin_longitude,
          destination_latitude, destination_longitude,
          direct_distance_meters, bike_id, trip_cost,
          pit_stops_json, stage_ids_json, stage_details_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id, external_id) DO UPDATE SET
          id = excluded.id,
          origin_station_id = excluded.origin_station_id,
          origin_station_name = excluded.origin_station_name,
          destination_station_id = excluded.destination_station_id,
          destination_station_name = excluded.destination_station_name,
          started_at_ms = excluded.started_at_ms,
          duration_seconds = excluded.duration_seconds,
          is_shared = excluded.is_shared,
          origin_latitude = COALESCE(excluded.origin_latitude, origin_latitude),
          origin_longitude = COALESCE(excluded.origin_longitude, origin_longitude),
          destination_latitude = COALESCE(excluded.destination_latitude, destination_latitude),
          destination_longitude = COALESCE(excluded.destination_longitude, destination_longitude),
          direct_distance_meters = COALESCE(excluded.direct_distance_meters, direct_distance_meters),
          bike_id = COALESCE(excluded.bike_id, bike_id),
          trip_cost = COALESCE(excluded.trip_cost, trip_cost),
          pit_stops_json = CASE
            WHEN excluded.pit_stops_json = '[]' THEN pit_stops_json
            ELSE excluded.pit_stops_json
          END,
          stage_ids_json = CASE
            WHEN excluded.stage_ids_json = '[]' THEN stage_ids_json
            ELSE excluded.stage_ids_json
          END,
          stage_details_json = CASE
            WHEN excluded.stage_details_json = '[]' THEN stage_details_json
            ELSE excluded.stage_details_json
          END
        ''', _tripValues(trip));
    }
  }

  static List<Object?> _tripValues(Trip trip) => [
    trip.userId,
    trip.externalId,
    trip.id,
    trip.originStationId,
    trip.originStationName,
    trip.destinationStationId,
    trip.destinationStationName,
    trip.startedAt.millisecondsSinceEpoch,
    trip.durationSeconds,
    trip.isShared ? 1 : 0,
    trip.originLatitude,
    trip.originLongitude,
    trip.destinationLatitude,
    trip.destinationLongitude,
    trip.directDistanceMeters,
    normalizeBikeId(trip.bikeId),
    trip.tripCost,
    jsonEncode([for (final pitStop in trip.pitStops) pitStop.toJson()]),
    jsonEncode(trip.stageIds),
    jsonEncode([for (final details in trip.stageDetails) details.toJson()]),
  ];

  static Trip _tripFromRow(Row row) {
    return Trip(
      id: row['id'] as String,
      externalId: row['external_id'] as String,
      userId: row['user_id'] as String,
      originStationId: row['origin_station_id'] as String,
      originStationName: row['origin_station_name'] as String,
      destinationStationId: row['destination_station_id'] as String,
      destinationStationName: row['destination_station_name'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row['started_at_ms'] as int,
      ),
      durationSeconds: row['duration_seconds'] as int,
      isShared: (row['is_shared'] as int) == 1,
      originLatitude: (row['origin_latitude'] as num?)?.toDouble(),
      originLongitude: (row['origin_longitude'] as num?)?.toDouble(),
      destinationLatitude: (row['destination_latitude'] as num?)?.toDouble(),
      destinationLongitude: (row['destination_longitude'] as num?)?.toDouble(),
      directDistanceMeters: (row['direct_distance_meters'] as num?)?.toDouble(),
      bikeId: normalizeBikeId(row['bike_id']),
      tripCost: row['trip_cost'] as String?,
      pitStops: _pitStopsFromJson(row['pit_stops_json'] as String),
      stageIds: _stringListFromJson(row['stage_ids_json'] as String),
      stageDetails: _stageDetailsFromJson(row['stage_details_json'] as String),
    );
  }

  static List<Trip> _decodeLegacyTrips(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('El almacenamiento legacy no es una lista.');
    }
    return [
      for (final item in decoded)
        if (item is Map) _tripFromLegacyJson(Map<String, Object?>.from(item)),
    ];
  }

  static Map<String, Set<String>> _decodeLegacyKnownIds(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Los IDs legacy no son un objeto.');
    }
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): {
          if (entry.value is List)
            for (final value in entry.value as List)
              if (value is String && value.isNotEmpty) value,
        },
    };
  }

  static Trip _tripFromLegacyJson(Map<String, Object?> json) {
    return Trip(
      id: json['id'] as String,
      externalId: json['externalId'] as String,
      userId: json['userId'] as String,
      originStationId: json['originStationId'] as String,
      originStationName: json['originStationName'] as String,
      destinationStationId: json['destinationStationId'] as String,
      destinationStationName: json['destinationStationName'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      durationSeconds: json['durationSeconds'] as int,
      isShared: json['isShared'] as bool,
      originLatitude: (json['originLatitude'] as num?)?.toDouble(),
      originLongitude: (json['originLongitude'] as num?)?.toDouble(),
      destinationLatitude: (json['destinationLatitude'] as num?)?.toDouble(),
      destinationLongitude: (json['destinationLongitude'] as num?)?.toDouble(),
      directDistanceMeters: (json['directDistanceMeters'] as num?)?.toDouble(),
      bikeId: normalizeBikeId(json['bikeId']),
      tripCost: json['tripCost'] as String?,
      pitStops: _pitStopsFromObject(json['pitStops']),
      stageIds: _stringListFromObject(json['stageIds']),
      stageDetails: _stageDetailsFromObject(json['stageDetails']),
    );
  }

  static List<PitStop> _pitStopsFromJson(String value) {
    return _pitStopsFromObject(jsonDecode(value));
  }

  static List<PitStop> _pitStopsFromObject(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map) ?PitStop.fromJson(Map<String, Object?>.from(item)),
    ].whereType<PitStop>().toList(growable: false);
  }

  static List<String> _stringListFromJson(String value) {
    return _stringListFromObject(jsonDecode(value));
  }

  static List<String> _stringListFromObject(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }

  static List<JourneyStageDetails> _stageDetailsFromJson(String value) {
    return _stageDetailsFromObject(jsonDecode(value));
  }

  static List<JourneyStageDetails> _stageDetailsFromObject(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map)
          ?JourneyStageDetails.fromJson(Map<String, Object?>.from(item)),
    ].whereType<JourneyStageDetails>().toList(growable: false);
  }

  static void _upsertKnownIdsSync(
    Database database,
    Map<String, Set<String>> knownIds,
  ) {
    for (final entry in knownIds.entries) {
      for (final externalId in entry.value) {
        _upsertKnownIdSync(database, entry.key, externalId);
      }
    }
  }

  static void _upsertKnownIdSync(
    Database database,
    String userId,
    String externalId,
  ) {
    database.execute(
      '''
      INSERT OR IGNORE INTO known_source_trip_ids(user_id, external_id)
      VALUES (?, ?)
      ''',
      [userId, externalId],
    );
  }

  static bool _containsExpectedIds(
    Database database,
    Map<String, Set<String>> expected,
  ) {
    for (final entry in expected.entries) {
      final rows = database.select(
        'SELECT external_id FROM known_source_trip_ids WHERE user_id = ?',
        [entry.key],
      );
      final actual = {for (final row in rows) row['external_id'] as String};
      if (!actual.containsAll(entry.value)) {
        return false;
      }
    }
    return true;
  }

  static String? _metadataValue(Database database, String key) {
    final rows = database.select(
      'SELECT value FROM app_metadata WHERE key = ?',
      [key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  static void _purgeDiscardedStationTrips(Database database) {
    if (_metadataValue(database, _discardedStationTripsMigrationKey) ==
        'completed') {
      return;
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      final rows = database.select('SELECT * FROM personal_trips');
      for (final row in rows) {
        final trip = _tripFromRow(row);
        if (!isCountableBicimadStage(trip)) {
          database.execute(
            'DELETE FROM personal_trips WHERE user_id = ? AND external_id = ?',
            [trip.userId, trip.externalId],
          );
        }
      }
      database.execute(
        'INSERT OR REPLACE INTO app_metadata(key, value) VALUES (?, ?)',
        [_discardedStationTripsMigrationKey, 'completed'],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static Future<void> _deleteLegacyBestEffort(SecureKeyValueStore store) async {
    try {
      await store.delete(legacyTripsStorageKey);
      await store.delete(legacyKnownIdsStorageKey);
    } catch (_) {
      // The verified SQLite copy remains authoritative; cleanup retries later.
    }
  }
}
