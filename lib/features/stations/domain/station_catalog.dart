import '../../trips/domain/station_code.dart';
import 'station.dart';

class StationCatalog {
  StationCatalog({required List<Station> stations, required this.updatedAt})
    : _byId = {for (final station in stations) station.id: station},
      _byPublicCode = {
        for (final station in stations) station.publicCode: station,
      },
      _byNormalizedName = {
        for (final station in stations)
          normalizeStationName(station.name): station,
      };

  final DateTime updatedAt;
  final Map<String, Station> _byId;
  final Map<String, Station> _byPublicCode;
  final Map<String, Station> _byNormalizedName;

  List<Station> get stations => _byId.values.toList(growable: false);

  bool isOlderThan(Duration age, DateTime now) {
    return updatedAt.isBefore(now.subtract(age));
  }

  Station? resolve({required String stationId, required String stationName}) {
    final codeFromName = extractPublicStationCode(stationName);
    if (codeFromName != null) {
      final byCodeFromName = _resolveByPublicCode(codeFromName, stationName);
      if (byCodeFromName != null) {
        return byCodeFromName;
      }
    }

    final byName = _byNormalizedName[normalizeStationName(stationName)];
    if (byName != null) {
      return byName;
    }

    final id = stationId.trim();
    final byId = _byId[id];
    final idAsPublicCode = normalizeStationCode(id);
    if (idAsPublicCode != null) {
      final byPublicCode = _resolveByPublicCode(idAsPublicCode, stationName);
      if (byId != null && _sameNormalizedName(stationName, byId.name)) {
        return byId;
      }
      if (byPublicCode != null) {
        return byPublicCode;
      }
    }

    return byId;
  }

  Map<String, Object?> toJson() {
    return {
      'updated_at': updatedAt.toIso8601String(),
      'stations': [for (final station in stations) station.toJson()],
    };
  }

  static StationCatalog? fromJson(Map<String, Object?> json) {
    final updatedAtRaw = json['updated_at'] ?? json['generated_at'];
    final rawStations = json['stations'];
    if (updatedAtRaw is! String || rawStations is! List) {
      return null;
    }
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      return null;
    }
    final stations = <Station>[];
    for (final item in rawStations) {
      if (item is! Map) {
        continue;
      }
      final station = Station.fromJson(Map<String, Object?>.from(item));
      if (station != null) {
        stations.add(station);
      }
    }
    if (stations.isEmpty) {
      return null;
    }
    return StationCatalog(stations: stations, updatedAt: updatedAt);
  }

  Station? _resolveByPublicCode(String code, String stationName) {
    final normalizedName = normalizeStationName(stationName);
    if (normalizedName.isNotEmpty) {
      final byName = _byNormalizedName[normalizedName];
      if (byName != null && byName.publicCode == code) {
        return byName;
      }
    }
    return _byPublicCode[code];
  }

  bool _sameNormalizedName(String left, String right) {
    final normalizedLeft = normalizeStationName(left);
    return normalizedLeft.isNotEmpty &&
        normalizedLeft == normalizeStationName(right);
  }
}

String normalizeStationName(String value) {
  final lower = value.trim().toLowerCase();
  final noPrefix = lower.replaceFirst(RegExp(r'^\s*\d+\s*-\s*'), '');
  return noPrefix
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
