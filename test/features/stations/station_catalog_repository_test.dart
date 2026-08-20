import 'dart:convert';

import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/features/stations/data/station_catalog_repository.dart';
import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/stations/domain/station_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test('resuelve estaciones por id, codigo publico y nombre normalizado', () {
    final catalog = StationCatalog(
      stations: const [
        Station(
          id: 'gbfs-1',
          publicCode: '34',
          name: 'Jacinto Benavente',
          latitude: 40.41,
          longitude: -3.70,
        ),
        Station(
          id: 'gbfs-2',
          publicCode: '99',
          name: 'Otra estacion',
          latitude: 40.42,
          longitude: -3.71,
        ),
      ],
      updatedAt: DateTime(2026, 8, 2),
    );

    expect(
      catalog.resolve(stationId: 'gbfs-1', stationName: 'Otro')?.publicCode,
      '34',
    );
    expect(
      catalog.resolve(stationId: 'internal', stationName: '34 - Otro')?.id,
      'gbfs-1',
    );
    expect(
      catalog.resolve(stationId: 'gbfs-2', stationName: '34 - Otro')?.id,
      'gbfs-1',
    );
    expect(
      catalog
          .resolve(stationId: 'internal', stationName: 'jacinto benavente')
          ?.id,
      'gbfs-1',
    );
  });

  test('prioriza codigo publico frente a station_id numerico del GBFS', () {
    final catalog = StationCatalog(
      stations: const [
        Station(
          id: '172',
          publicCode: '160',
          name: 'Colombia',
          latitude: 40.45,
          longitude: -3.67,
        ),
        Station(
          id: '180',
          publicCode: '172',
          name: 'Delicias',
          latitude: 40.40,
          longitude: -3.69,
        ),
      ],
      updatedAt: DateTime(2026, 8, 2),
    );

    expect(
      catalog.resolve(stationId: '172', stationName: '172 - Delicias')?.name,
      'Delicias',
    );
    expect(
      catalog.resolve(stationId: '172', stationName: 'Delicias')?.name,
      'Delicias',
    );
    expect(
      catalog.resolve(stationId: '172', stationName: 'Colombia')?.name,
      'Colombia',
    );
  });

  test(
    'desambigua estaciones con el mismo codigo publico usando el nombre',
    () {
      final catalog = StationCatalog(
        stations: const [
          Station(
            id: '1',
            publicCode: '1',
            name: 'Puerta del Sol A',
            latitude: 40.41,
            longitude: -3.70,
          ),
          Station(
            id: '2',
            publicCode: '1',
            name: 'Puerta del Sol B',
            latitude: 40.42,
            longitude: -3.71,
          ),
        ],
        updatedAt: DateTime(2026, 8, 2),
      );

      expect(
        catalog
            .resolve(stationId: '1', stationName: '1 - Puerta del Sol A')
            ?.id,
        '1',
      );
      expect(
        catalog
            .resolve(stationId: '1', stationName: '1 - Puerta del Sol B')
            ?.id,
        '2',
      );
    },
  );

  test(
    'actualiza desde GBFS en segundo plano si el catalogo esta caducado',
    () async {
      final store = InMemorySecureKeyValueStore();
      final transport = QueuedHttpTransport([
        HttpResponseData(
          statusCode: 200,
          body: jsonEncode({
            'data': {
              'stations': [
                {
                  'station_id': 'station-1',
                  'short_name': '34',
                  'name': 'Jacinto Benavente',
                  'lat': 40.41,
                  'lon': -3.70,
                },
              ],
            },
          }),
          headers: const {},
        ),
      ]);
      await store.write(
        key: 'stations.catalog.v2',
        value: jsonEncode({
          'updated_at': DateTime(2026, 7, 1).toIso8601String(),
          'stations': [
            {
              'id': 'old',
              'public_code': '1',
              'name': 'Antigua',
              'latitude': 40.0,
              'longitude': -3.0,
            },
          ],
        }),
      );
      final repository = LocalStationCatalogRepository(
        store: store,
        transport: transport,
        now: () => DateTime(2026, 8, 2),
      );

      final catalog = await repository.getCatalog();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        catalog.resolve(stationId: 'old', stationName: 'Antigua'),
        isNotNull,
      );
      expect(transport.requests, hasLength(1));
      expect(store.values['stations.catalog.v2'], contains('station-1'));
    },
  );

  test('si falla GBFS conserva el ultimo catalogo valido', () async {
    final store = InMemorySecureKeyValueStore();
    final transport = QueuedHttpTransport([
      const HttpResponseData(statusCode: 500, body: '{}', headers: {}),
    ]);
    await store.write(
      key: 'stations.catalog.v2',
      value: jsonEncode({
        'updated_at': DateTime(2026, 7, 1).toIso8601String(),
        'stations': [
          {
            'id': 'old',
            'public_code': '1',
            'name': 'Antigua',
            'latitude': 40.0,
            'longitude': -3.0,
          },
        ],
      }),
    );
    final repository = LocalStationCatalogRepository(
      store: store,
      transport: transport,
      now: () => DateTime(2026, 8, 2),
    );

    final catalog = await repository.getCatalog();
    await Future<void>.delayed(Duration.zero);

    expect(
      catalog.resolve(stationId: 'old', stationName: 'Antigua'),
      isNotNull,
    );
    expect(store.values['stations.catalog.v2'], contains('Antigua'));
  });

  test('prioriza el codigo publico del nombre frente a short_name', () async {
    final store = InMemorySecureKeyValueStore();
    await store.write(
      key: 'stations.catalog.v2',
      value: jsonEncode({
        'updated_at': DateTime(2026, 7, 1).toIso8601String(),
        'stations': [
          {
            'id': 'old',
            'public_code': '1',
            'name': 'Antigua',
            'latitude': 40.0,
            'longitude': -3.0,
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
                'station_id': '130',
                'short_name': '130',
                'name': '122 - Santa Engracia - Zurbarán',
                'lat': 40.4291992,
                'lon': -3.6967169,
              },
            ],
          },
        }),
        headers: const {},
      ),
    ]);
    final repository = LocalStationCatalogRepository(
      store: store,
      transport: transport,
      now: () => DateTime(2026, 8, 2),
    );

    repository.refreshInBackground(force: true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final catalog = await repository.getCatalog();

    expect(
      catalog
          .resolve(
            stationId: '122',
            stationName: '122 - Santa Engracia - Zurbarán',
          )
          ?.publicCode,
      '122',
    );
  });
}
