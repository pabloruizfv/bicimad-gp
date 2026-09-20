import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/terrain_elevation_grid.dart';

abstract interface class TerrainElevationRepository {
  Future<String> version();

  Future<TerrainElevationGrid> load();
}

class AssetTerrainElevationRepository implements TerrainElevationRepository {
  AssetTerrainElevationRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const _metadataAsset = 'assets/data/station_terrain_10m.json';
  static const _gridAsset = 'assets/data/station_terrain_10m.i16.gz';

  final AssetBundle _bundle;
  Future<Map<Object?, Object?>>? _metadataFuture;
  Future<TerrainElevationGrid>? _cached;

  @override
  Future<String> version() async {
    final metadata = await _metadata();
    final value = metadata['grid_sha256'];
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('Invalid terrain version.');
    }
    return value;
  }

  @override
  Future<TerrainElevationGrid> load() =>
      _cached ??= _load().catchError((Object error, StackTrace stackTrace) {
        _cached = null;
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<TerrainElevationGrid> _load() async {
    final metadata = await _metadata();
    if (metadata['format_version'] != 1 ||
        metadata['encoding'] != 'gzip-int16-little-endian') {
      throw const FormatException('Invalid terrain metadata.');
    }
    final compressed = await _bundle.load(_gridAsset);
    final bytes = await compute(
      _decompressGrid,
      compressed.buffer.asUint8List(
        compressed.offsetInBytes,
        compressed.lengthInBytes,
      ),
    );
    double number(String key) {
      final value = metadata[key];
      if (value is! num) throw FormatException('Invalid terrain $key.');
      return value.toDouble();
    }

    int integer(String key) {
      final value = metadata[key];
      if (value is! int) throw FormatException('Invalid terrain $key.');
      return value;
    }

    return TerrainElevationGrid(
      west: number('west'),
      south: number('south'),
      east: number('east'),
      north: number('north'),
      stepDegrees: number('step_degrees'),
      width: integer('width'),
      height: integer('height'),
      scaleMeters: number('scale_meters'),
      nodata: integer('nodata'),
      bytes: bytes,
    );
  }

  Future<Map<Object?, Object?>> _metadata() => _metadataFuture ??= () async {
    final decoded = jsonDecode(await _bundle.loadString(_metadataAsset));
    if (decoded is! Map) {
      throw const FormatException('Invalid terrain metadata.');
    }
    return decoded;
  }();
}

Uint8List _decompressGrid(Uint8List compressed) =>
    Uint8List.fromList(gzip.decode(compressed));
