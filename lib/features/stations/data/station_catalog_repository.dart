import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/network/http_transport.dart';
import '../../../core/storage/secure_key_value_store.dart';
import '../domain/station.dart';
import '../domain/station_catalog.dart';
import 'terrain_elevation_repository.dart';

abstract interface class StationCatalogRepository {
  Future<StationCatalog> getCatalog();

  void refreshInBackground({bool force = false});

  Future<void> refreshIfUnknown({
    required String stationId,
    required String stationName,
  });
}

class LocalStationCatalogRepository implements StationCatalogRepository {
  LocalStationCatalogRepository({
    required this.store,
    required this.transport,
    this.terrainRepository,
    this.assetPath = 'assets/data/station_catalog_snapshot.json',
    this.gbfsStationInformationUri = const String.fromEnvironment(
      'BICIMAD_GBFS_STATION_INFORMATION_URL',
      defaultValue:
          'https://madrid.publicbikesystem.net/customer/gbfs/v3.0/gbfs.json',
    ),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _catalogStorageKey = 'stations.catalog.v2';
  static const _staleAfter = Duration(days: 7);

  final SecureKeyValueStore store;
  final HttpTransport transport;
  final TerrainElevationRepository? terrainRepository;
  final String assetPath;
  final String gbfsStationInformationUri;
  final DateTime Function() _now;

  StationCatalog? _cachedCatalog;
  Future<void>? _refreshFuture;

  @override
  Future<StationCatalog> getCatalog() async {
    final cached = _cachedCatalog;
    if (cached != null) {
      _refreshIfStale(cached);
      return cached;
    }

    final stored = await _readStoredCatalog();
    if (stored != null) {
      final enriched = await _withTerrainElevations(stored);
      _cachedCatalog = enriched;
      if (!identical(enriched, stored)) await _persistCatalog(enriched);
      _refreshIfStale(enriched);
      return enriched;
    }

    final assetCatalog = await _withTerrainElevations(
      await _readAssetCatalog(),
    );
    _cachedCatalog = assetCatalog;
    await _persistCatalog(assetCatalog);
    _refreshIfStale(assetCatalog);
    return assetCatalog;
  }

  @override
  void refreshInBackground({bool force = false}) {
    if (_refreshFuture != null) {
      return;
    }
    unawaited(
      _refreshFuture = _refreshFromGbfs(force: force).whenComplete(() {
        _refreshFuture = null;
      }),
    );
  }

  @override
  Future<void> refreshIfUnknown({
    required String stationId,
    required String stationName,
  }) async {
    final catalog = await getCatalog();
    if (catalog.resolve(stationId: stationId, stationName: stationName) ==
        null) {
      // A missing station is discovered while enriching a trip, so wait for
      // this targeted refresh. Normal startup still uses getCatalog() without
      // waiting for GBFS.
      await _refreshFromGbfs(force: true);
    }
  }

  void _refreshIfStale(StationCatalog catalog) {
    if (catalog.isOlderThan(_staleAfter, _now())) {
      refreshInBackground(force: true);
    }
  }

  Future<StationCatalog?> _readStoredCatalog() async {
    final raw = await store.read(_catalogStorageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return StationCatalog.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<StationCatalog> _readAssetCatalog() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Catalogo de estaciones invalido.');
    }
    final catalog = StationCatalog.fromJson(Map<String, Object?>.from(decoded));
    if (catalog == null) {
      throw StateError('Catalogo de estaciones invalido.');
    }
    return catalog;
  }

  Future<void> _refreshFromGbfs({required bool force}) async {
    if (!force) {
      final catalog = _cachedCatalog ?? await _readStoredCatalog();
      if (catalog != null && !catalog.isOlderThan(_staleAfter, _now())) {
        return;
      }
    }

    try {
      final response = await transport.get(
        Uri.parse(gbfsStationInformationUri),
        headers: const {},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return;
      }
      var stations = _stationsFromGbfs(Map<String, Object?>.from(decoded));
      if (stations.isEmpty) {
        final stationInformationUrl = _findStationInformationUrl(decoded);
        if (stationInformationUrl == null) {
          return;
        }
        final stationResponse = await transport.get(
          Uri.parse(
            Uri.parse(
              gbfsStationInformationUri,
            ).resolve(stationInformationUrl).toString(),
          ),
          headers: const {},
        );
        if (stationResponse.statusCode < 200 ||
            stationResponse.statusCode >= 300) {
          return;
        }
        final stationPayload = jsonDecode(stationResponse.body);
        if (stationPayload is! Map) {
          return;
        }
        stations = _stationsFromGbfs(Map<String, Object?>.from(stationPayload));
      }
      if (stations.isEmpty) {
        return;
      }
      final catalog = await _withTerrainElevations(
        StationCatalog(stations: stations, updatedAt: _now()),
      );
      _cachedCatalog = catalog;
      await _persistCatalog(catalog);
    } catch (_) {
      // Keep the last valid catalog. Catalog refresh must never block startup.
    }
  }

  Future<void> _persistCatalog(StationCatalog catalog) {
    return store.write(
      key: _catalogStorageKey,
      value: jsonEncode(catalog.toJson()),
    );
  }

  Future<StationCatalog> _withTerrainElevations(StationCatalog catalog) async {
    final terrain = terrainRepository;
    if (terrain == null) return catalog;
    try {
      final version = await terrain.version();
      if (catalog.elevationGridVersion == version) return catalog;
      final grid = await terrain.load();
      final stations = [
        for (final station in catalog.stations)
          () {
            final elevation = grid.elevationAt(
              latitude: station.latitude,
              longitude: station.longitude,
            );
            return station.withElevation(elevation);
          }(),
      ];
      return StationCatalog(
        stations: stations,
        updatedAt: catalog.updatedAt,
        elevationGridVersion: version,
      );
    } catch (_) {
      return catalog;
    }
  }

  List<Station> _stationsFromGbfs(Map<String, Object?> payload) {
    final data = payload['data'];
    if (data is! Map) {
      return const [];
    }
    final stations = data['stations'];
    if (stations is! List) {
      return const [];
    }
    final parsedStations = <Station>[];
    for (final item in stations) {
      if (item is! Map) {
        continue;
      }
      final station = _stationFromGbfs(Map<String, Object?>.from(item));
      if (station != null) {
        parsedStations.add(station);
      }
    }
    return parsedStations;
  }

  String? _findStationInformationUrl(Object? value) {
    if (value is Map) {
      final name = value['name']?.toString().toLowerCase() ?? '';
      final url = value['url'];
      if (name.contains('station_information') && url is String) {
        return url;
      }
      for (final item in value.values) {
        final found = _findStationInformationUrl(item);
        if (found != null) {
          return found;
        }
      }
    } else if (value is List) {
      for (final item in value) {
        final found = _findStationInformationUrl(item);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  Station? _stationFromGbfs(Map<String, Object?> json) {
    final id = (json['station_id'] ?? json['id'])?.toString().trim();
    final name = json['name']?.toString().trim();
    final lat = json['lat'];
    final lon = json['lon'];
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        lat is! num ||
        lon is! num) {
      return null;
    }
    // The public code is the numeric prefix in the station name. GBFS
    // short_name may contain an internal identifier instead.
    final publicCode =
        _numericPrefix(name) ?? _numericPrefix(json['short_name']?.toString());
    if (publicCode == null) {
      return null;
    }
    return Station(
      id: id,
      publicCode: publicCode,
      name: name,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
    );
  }

  String? _numericPrefix(String? value) {
    final match = RegExp(r'^\s*(\d+)').firstMatch(value ?? '');
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!).toString();
  }
}
