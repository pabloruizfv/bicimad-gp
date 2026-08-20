import 'dart:convert';
import 'dart:io';

import 'package:bicimad_social/features/rankings/domain/route_key.dart';
import 'package:bicimad_social/features/trips/data/legacy_route_model_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copia la DB persistente una vez y la reutiliza', () async {
    final bytes = await _createDatabaseBytes();
    final assets = _FixtureAssetBundle(
      databaseBytes: bytes,
      manifest: _manifest(bytes, version: 'v1'),
    );
    final supportDirectory = await Directory.systemTemp.createTemp(
      'legacy_asset_store_test_',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final store = LegacyDatabaseAssetStore(
      assetBundle: assets,
      directoryProvider: () async => supportDirectory,
    );

    final firstPath = await store.ensureDatabase();
    final secondPath = await store.ensureDatabase();

    expect(secondPath, firstPath);
    expect(File(firstPath).existsSync(), isTrue);
    expect(assets.databaseLoads, 1);
  });

  test('una version nueva del asset crea y valida una copia nueva', () async {
    final bytes = await _createDatabaseBytes();
    final assets = _FixtureAssetBundle(
      databaseBytes: bytes,
      manifest: _manifest(bytes, version: 'v1'),
    );
    final supportDirectory = await Directory.systemTemp.createTemp(
      'legacy_asset_version_test_',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final store = LegacyDatabaseAssetStore(
      assetBundle: assets,
      directoryProvider: () async => supportDirectory,
    );

    final firstPath = await store.ensureDatabase();
    assets.manifest = _manifest(bytes, version: 'v2');
    final secondPath = await store.ensureDatabase();

    expect(secondPath, isNot(firstPath));
    expect(File(secondPath).existsSync(), isTrue);
    expect(assets.databaseLoads, 2);
  });

  test('resuelve muchas OD en un batch, distingue sentidos y cachea', () async {
    final path = await _createDatabasePath();
    addTearDown(() => File(path).parent.delete(recursive: true));
    var queryCount = 0;
    final repository = SqliteLegacyRouteModelRepository(
      databasePath: path,
      onQuery: () => queryCount += 1,
    );
    addTearDown(repository.close);
    const forward = RouteKey(
      originStationId: '34',
      destinationStationId: '164',
    );
    const reverse = RouteKey(
      originStationId: '164',
      destinationStationId: '34',
    );
    const missing = RouteKey(originStationId: '1', destinationStationId: '2');

    final models = await repository.getRouteModels({forward, reverse, missing});
    final cachedModels = await repository.getRouteModels({
      forward,
      reverse,
      missing,
    });

    expect(models[forward]?.bestSeconds, 60);
    expect(models[reverse]?.bestSeconds, 90);
    expect(models, isNot(contains(missing)));
    expect(cachedModels.keys, containsAll([forward, reverse]));
    expect(queryCount, 1);
  });
}

class _FixtureAssetBundle extends CachingAssetBundle {
  _FixtureAssetBundle({required this.databaseBytes, required this.manifest});

  final Uint8List databaseBytes;
  String manifest;
  int databaseLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.sqlite')) {
      databaseLoads += 1;
      return ByteData.sublistView(databaseBytes);
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(manifest)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => manifest;
}

String _manifest(Uint8List bytes, {required String version}) {
  return jsonEncode({
    'version': version,
    'size': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
  });
}

Future<Uint8List> _createDatabaseBytes() async {
  final path = await _createDatabasePath();
  final file = File(path);
  final bytes = await file.readAsBytes();
  await file.parent.delete(recursive: true);
  return bytes;
}

Future<String> _createDatabasePath() async {
  final directory = await Directory.systemTemp.createTemp(
    'legacy_batch_db_test_',
  );
  final file = File('${directory.path}/legacy.sqlite');
  final database = sqlite3.open(file.path);
  try {
    database.execute('''
      CREATE TABLE route_models (
        origin_station_code TEXT NOT NULL,
        destination_station_code TEXT NOT NULL,
        origin_station_name TEXT NOT NULL,
        destination_station_name TEXT NOT NULL,
        total_count INTEGER NOT NULL,
        displayed_count INTEGER NOT NULL,
        outlier_count INTEGER NOT NULL,
        upper_cutoff_seconds REAL NOT NULL,
        best_seconds REAL NOT NULL,
        bin_edges TEXT NOT NULL,
        bin_counts TEXT NOT NULL,
        first_trip_at TEXT NOT NULL,
        last_trip_at TEXT NOT NULL,
        model_family TEXT NOT NULL,
        model_version TEXT NOT NULL,
        PRIMARY KEY (origin_station_code, destination_station_code)
      );
    ''');
    _insertModel(database, origin: '34', destination: '164', best: 60);
    _insertModel(database, origin: '164', destination: '34', best: 90);
  } finally {
    database.close();
  }
  return file.path;
}

void _insertModel(
  Database database, {
  required String origin,
  required String destination,
  required double best,
}) {
  database.execute(
    '''
    INSERT INTO route_models VALUES (
      ?, ?, 'Origen', 'Destino',
      30, 30, 0, 220.0, ?, '[60,100,140,180,220]', '[2,3,4,21]',
      '2023-01-01T00:00:00', '2023-12-31T00:00:00',
      'empirical_histogram', 'test'
    )
    ''',
    [origin, destination, best],
  );
}
