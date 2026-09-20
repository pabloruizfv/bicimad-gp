import 'dart:convert';
import 'dart:typed_data';

import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/features/stations/data/station_catalog_repository.dart';
import 'package:bicimad_social/features/stations/data/terrain_elevation_repository.dart';
import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/stations/domain/terrain_elevation_grid.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/domain/trip_elevation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('interpolates terrain elevations and rejects unknown locations', () {
    final grid = _fixtureGrid();
    expect(grid.elevationAt(latitude: 40.5, longitude: -3.5), 100);
    expect(grid.elevationAt(latitude: 40.0, longitude: -3.0), 250);
    expect(grid.elevationAt(latitude: 39.5, longitude: -2.5), 400);
    expect(grid.elevationAt(latitude: 42.0, longitude: -3.0), isNull);
  });

  test('does not interpolate across missing terrain cells', () {
    final grid = _fixtureGrid(values: [1000, -32768, 3000, 4000]);
    expect(grid.elevationAt(latitude: 40.5, longitude: -3.5), 100);
    expect(grid.elevationAt(latitude: 40.0, longitude: -3.0), isNull);
  });

  test('station elevation survives JSON roundtrip', () {
    const station = Station(
      id: '1',
      publicCode: '1',
      name: 'Station',
      latitude: 40.5,
      longitude: -3.5,
      elevationMeters: 100.5,
    );
    expect(Station.fromJson(station.toJson())?.elevationMeters, 100.5);
  });

  test(
    'new or moved GBFS station gets the elevation of its coordinates',
    () async {
      final store = InMemorySecureKeyValueStore();
      await store.write(
        key: 'stations.catalog.v2',
        value: jsonEncode({
          'updated_at': DateTime(2026, 8, 1).toIso8601String(),
          'stations': [
            {
              'id': 'existing',
              'public_code': '1',
              'name': 'Existing',
              'latitude': 40.5,
              'longitude': -3.5,
              'elevation_meters': 100.0,
            },
          ],
        }),
      );
      final transport = QueuedHttpTransport([
        HttpResponseData(
          statusCode: 200,
          body: jsonEncode({
            'data': {
              'stations': [
                {
                  'station_id': 'new',
                  'name': '2 - New station',
                  'lat': 39.5,
                  'lon': -2.5,
                },
              ],
            },
          }),
          headers: const {},
        ),
        HttpResponseData(
          statusCode: 200,
          body: jsonEncode({
            'data': {
              'stations': [
                {
                  'station_id': 'new',
                  'name': '2 - New station',
                  'lat': 40.5,
                  'lon': -3.5,
                },
              ],
            },
          }),
          headers: const {},
        ),
      ]);
      final terrain = _FixtureTerrainRepository(_fixtureGrid());
      final repository = LocalStationCatalogRepository(
        store: store,
        transport: transport,
        terrainRepository: terrain,
        now: () => DateTime(2026, 8, 2),
      );

      repository.refreshInBackground(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final updated = await repository.getCatalog();
      expect(
        updated
            .resolve(stationId: 'new', stationName: '2 - New station')
            ?.elevationMeters,
        400,
      );
      expect(store.values['stations.catalog.v2'], contains('elevation_meters'));
      repository.refreshInBackground(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final moved = await repository.getCatalog();
      expect(
        moved
            .resolve(stationId: 'new', stationName: '2 - New station')
            ?.elevationMeters,
        100,
      );
      expect(terrain.loads, 2);
    },
  );

  test('old catalog is enriched without losing stations', () async {
    final store = InMemorySecureKeyValueStore();
    await store.write(
      key: 'stations.catalog.v2',
      value: jsonEncode({
        'updated_at': DateTime(2026, 8, 2).toIso8601String(),
        'stations': [
          {
            'id': 'old',
            'public_code': '1',
            'name': 'Old',
            'latitude': 40.5,
            'longitude': -3.5,
          },
        ],
      }),
    );
    final repository = LocalStationCatalogRepository(
      store: store,
      transport: QueuedHttpTransport([]),
      terrainRepository: _FixtureTerrainRepository(_fixtureGrid()),
      now: () => DateTime(2026, 8, 2),
    );
    final catalog = await repository.getCatalog();
    expect(catalog.stations, hasLength(1));
    expect(catalog.stations.single.elevationMeters, 100);
    expect(store.values['stations.catalog.v2'], contains('elevation_meters'));
  });

  test(
    'cached elevation is recalculated when the terrain version changes',
    () async {
      final store = InMemorySecureKeyValueStore();
      await store.write(
        key: 'stations.catalog.v2',
        value: jsonEncode({
          'updated_at': DateTime(2026, 8, 2).toIso8601String(),
          'elevation_grid_version': 'fixture-v1',
          'stations': [
            {
              'id': 'station',
              'public_code': '1',
              'name': 'Station',
              'latitude': 40.5,
              'longitude': -3.5,
              'elevation_meters': 100.0,
            },
          ],
        }),
      );
      final terrain = _FixtureTerrainRepository(_fixtureGrid());
      LocalStationCatalogRepository repository() =>
          LocalStationCatalogRepository(
            store: store,
            transport: QueuedHttpTransport([]),
            terrainRepository: terrain,
            now: () => DateTime(2026, 8, 2),
          );

      expect(
        (await repository().getCatalog()).stations.single.elevationMeters,
        100,
      );
      expect(terrain.loads, 0);
      terrain.currentVersion = 'fixture-v2';
      terrain.grid = _fixtureGrid(values: [1100, 2000, 3000, 4000]);
      final updated = await repository().getCatalog();
      expect(updated.stations.single.elevationMeters, 110);
      expect(updated.elevationGridVersion, 'fixture-v2');
      expect(terrain.loads, 1);
    },
  );

  test('trip profile calculates signed net differences per leg', () {
    final trip = Trip(
      id: 'journey',
      externalId: 'stage',
      userId: 'user',
      originStationId: 'A',
      originStationName: 'A',
      destinationStationId: 'C',
      destinationStationName: 'C',
      startedAt: DateTime(2026, 8, 1),
      durationSeconds: 600,
      isShared: false,
      originLatitude: 40.5,
      originLongitude: -3.5,
      destinationLatitude: 39.5,
      destinationLongitude: -2.5,
      pitStops: const [
        PitStop(
          stationId: 'B',
          stationName: 'B',
          durationSeconds: 10,
          latitude: 39.5,
          longitude: -3.5,
        ),
      ],
    );
    final result = TripElevationCalculator(_fixtureGrid()).forTrip(trip);
    expect(result.segmentNetMeters, [200, 100]);
    expect(result.netMeters, 300);
  });

  test('bundled terrain covers the shipped station catalog', () async {
    final grid = await AssetTerrainElevationRepository().load();
    final store = InMemorySecureKeyValueStore();
    final catalog = await LocalStationCatalogRepository(
      store: store,
      transport: QueuedHttpTransport([]),
      terrainRepository: _FixtureTerrainRepository(grid),
      now: () => DateTime(2026, 8, 2),
    ).getCatalog();
    expect(catalog.stations.length, greaterThan(600));
    for (final station in catalog.stations) {
      expect(
        grid.elevationAt(
          latitude: station.latitude,
          longitude: station.longitude,
        ),
        closeTo(station.elevationMeters!, 0.2),
      );
    }
  });
}

TerrainElevationGrid _fixtureGrid({
  List<int> values = const [1000, 2000, 3000, 4000],
}) {
  final bytes = Uint8List(values.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    data.setInt16(i * 2, values[i], Endian.little);
  }
  return TerrainElevationGrid(
    west: -4,
    south: 39,
    east: -2,
    north: 41,
    stepDegrees: 1,
    width: 2,
    height: 2,
    scaleMeters: 0.1,
    nodata: -32768,
    bytes: bytes,
  );
}

class _FixtureTerrainRepository implements TerrainElevationRepository {
  _FixtureTerrainRepository(this.grid);

  TerrainElevationGrid grid;
  String currentVersion = 'fixture-v1';
  int loads = 0;

  @override
  Future<String> version() async => currentVersion;

  @override
  Future<TerrainElevationGrid> load() async {
    loads++;
    return grid;
  }
}
