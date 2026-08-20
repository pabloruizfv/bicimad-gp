import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/diagnostics/ranking_performance.dart';
import '../../rankings/domain/route_key.dart';
import '../domain/legacy_route_model.dart';

abstract interface class LegacyRouteModelRepository {
  Future<LegacyRouteModel?> getRouteModel({
    required String originStationCode,
    required String destinationStationCode,
  });

  Future<Map<RouteKey, LegacyRouteModel>> getRouteModels(Set<RouteKey> routes);

  void close();
}

class LegacyDatabaseAssetManifest {
  const LegacyDatabaseAssetManifest({
    required this.version,
    required this.size,
    required this.sha256,
  });

  factory LegacyDatabaseAssetManifest.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final size = json['size'];
    final hash = json['sha256'];
    if (version is! String ||
        version.trim().isEmpty ||
        size is! int ||
        size <= 0 ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException(
        'El manifiesto de la base historica no es valido.',
      );
    }
    return LegacyDatabaseAssetManifest(
      version: version,
      size: size,
      sha256: hash,
    );
  }

  final String version;
  final int size;
  final String sha256;
}

class LegacyDatabaseAssetStore {
  LegacyDatabaseAssetStore({
    this.assetPath = 'assets/data/legacy_route_models.sqlite',
    this.manifestAssetPath = 'assets/data/legacy_route_models.manifest.json',
    AssetBundle? assetBundle,
    Future<Directory> Function()? directoryProvider,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final String assetPath;
  final String manifestAssetPath;
  final AssetBundle _assetBundle;
  final Future<Directory> Function() _directoryProvider;

  Future<String> ensureDatabase() async {
    final stopwatch = Stopwatch()..start();
    try {
      final manifest = await _readManifest();
      final root = await _directoryProvider();
      final directory = Directory('${root.path}/legacy_route_models');
      await directory.create(recursive: true);
      final version = manifest.version.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final finalFile = File(
        '${directory.path}/legacy_route_models_${version}_${manifest.sha256}.sqlite',
      );

      if (await _hasExpectedSize(finalFile, manifest.size)) {
        return finalFile.path;
      }

      final bytes = await _loadAssetBytes(assetPath);
      _verifyAsset(bytes, manifest);
      final partialFile = File(
        '${finalFile.path}.partial.${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await partialFile.writeAsBytes(bytes, flush: true);
        _verifySqliteFile(partialFile.path);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await partialFile.rename(finalFile.path);
      } finally {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }
      await _deleteStaleCopies(directory, keepPath: finalFile.path);
      return finalFile.path;
    } finally {
      stopwatch.stop();
      logRankingPerformance('ensure_db_copy', stopwatch.elapsed);
    }
  }

  Future<LegacyDatabaseAssetManifest> _readManifest() async {
    final raw = await _assetBundle.loadString(manifestAssetPath, cache: true);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'El manifiesto de la base historica no es valido.',
      );
    }
    return LegacyDatabaseAssetManifest.fromJson(decoded);
  }

  Future<Uint8List> _loadAssetBytes(String path) async {
    final data = await _assetBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void _verifyAsset(Uint8List bytes, LegacyDatabaseAssetManifest manifest) {
    if (bytes.length != manifest.size ||
        sha256.convert(bytes).toString() != manifest.sha256) {
      throw const FormatException(
        'La base historica no coincide con su manifiesto.',
      );
    }
  }

  void _verifySqliteFile(String path) {
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final result = database.select('PRAGMA quick_check');
      if (result.isEmpty || result.first.values.first != 'ok') {
        throw const FormatException('La base historica copiada no es valida.');
      }
    } finally {
      database.close();
    }
  }

  Future<bool> _hasExpectedSize(File file, int expectedSize) async {
    return await file.exists() && await file.length() == expectedSize;
  }

  Future<void> _deleteStaleCopies(
    Directory directory, {
    required String keepPath,
  }) async {
    final normalizedKeepPath = _normalizePath(keepPath);
    await for (final entity in directory.list()) {
      if (entity is! File ||
          _normalizePath(entity.path) == normalizedKeepPath ||
          !entity.path.endsWith('.sqlite')) {
        continue;
      }
      try {
        await entity.delete();
      } on FileSystemException {
        // Another process may still have an old read-only copy open.
      }
    }
  }

  String _normalizePath(String path) {
    return File(path).absolute.path.replaceAll('\\', '/').toLowerCase();
  }
}

class SqliteLegacyRouteModelRepository implements LegacyRouteModelRepository {
  SqliteLegacyRouteModelRepository({
    this.databasePath,
    LegacyDatabaseAssetStore? assetStore,
    this.maxRoutesPerQuery = 400,
    this.onQuery,
  }) : _assetStore = assetStore ?? LegacyDatabaseAssetStore();

  final String? databasePath;
  final LegacyDatabaseAssetStore _assetStore;
  final int maxRoutesPerQuery;
  final void Function()? onQuery;
  final Map<RouteKey, LegacyRouteModel?> _modelCache = {};
  Database? _database;

  @override
  Future<LegacyRouteModel?> getRouteModel({
    required String originStationCode,
    required String destinationStationCode,
  }) async {
    final key = RouteKey(
      originStationId: originStationCode,
      destinationStationId: destinationStationCode,
    );
    final models = await getRouteModels({key});
    return models[key];
  }

  @override
  Future<Map<RouteKey, LegacyRouteModel>> getRouteModels(
    Set<RouteKey> routes,
  ) async {
    if (routes.isEmpty) {
      return const {};
    }

    final missing = [
      for (final route in routes)
        if (!_modelCache.containsKey(route)) route,
    ];
    if (missing.isNotEmpty) {
      final database = await _openDatabase();
      for (var start = 0; start < missing.length; start += maxRoutesPerQuery) {
        final end = (start + maxRoutesPerQuery).clamp(0, missing.length);
        _queryModels(database, missing.sublist(start, end));
      }
    }

    return {
      for (final route in routes)
        if (_modelCache[route] case final LegacyRouteModel model) route: model,
    };
  }

  @override
  void close() {
    _database?.close();
    _database = null;
    _modelCache.clear();
  }

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final path = databasePath ?? await _assetStore.ensureDatabase();
      final database = sqlite3.open(path, mode: OpenMode.readOnly);
      _database = database;
      return database;
    } finally {
      stopwatch.stop();
      logRankingPerformance('open_db', stopwatch.elapsed);
    }
  }

  void _queryModels(Database database, List<RouteKey> routes) {
    onQuery?.call();
    final placeholders = List.filled(routes.length, '(?, ?)').join(', ');
    final parameters = <Object?>[
      for (final route in routes) ...[
        route.originStationId,
        route.destinationStationId,
      ],
    ];
    final result = database.select('''
      SELECT
        origin_station_code,
        destination_station_code,
        origin_station_name,
        destination_station_name,
        total_count,
        displayed_count,
        outlier_count,
        upper_cutoff_seconds,
        best_seconds,
        bin_edges,
        bin_counts,
        first_trip_at,
        last_trip_at,
        model_family,
        model_version
      FROM route_models
      WHERE (origin_station_code, destination_station_code)
        IN (VALUES $placeholders)
      ''', parameters);

    final found = <RouteKey>{};
    for (final row in result) {
      final model = _modelFromRow(row);
      final key = RouteKey(
        originStationId: model.originStationCode,
        destinationStationId: model.destinationStationCode,
      );
      found.add(key);
      _modelCache[key] = model;
    }
    for (final route in routes) {
      if (!found.contains(route)) {
        _modelCache[route] = null;
      }
    }
  }

  LegacyRouteModel _modelFromRow(Row row) {
    return LegacyRouteModel(
      originStationCode: row['origin_station_code'] as String,
      destinationStationCode: row['destination_station_code'] as String,
      originStationName: row['origin_station_name'] as String,
      destinationStationName: row['destination_station_name'] as String,
      totalCount: row['total_count'] as int,
      displayedCount: row['displayed_count'] as int,
      outlierCount: row['outlier_count'] as int,
      upperCutoffSeconds: (row['upper_cutoff_seconds'] as num).toDouble(),
      bestSeconds: (row['best_seconds'] as num).toDouble(),
      binEdges: _doubleListFromJson(row['bin_edges'] as String),
      binCounts: _intListFromJson(row['bin_counts'] as String),
      firstTripAt: DateTime.parse(row['first_trip_at'] as String),
      lastTripAt: DateTime.parse(row['last_trip_at'] as String),
      modelFamily: row['model_family'] as String,
      modelVersion: row['model_version'] as String,
    );
  }

  List<double> _doubleListFromJson(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final item in decoded)
        if (item is num) item.toDouble(),
    ];
  }

  List<int> _intListFromJson(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final item in decoded)
        if (item is num) item.toInt(),
    ];
  }
}
