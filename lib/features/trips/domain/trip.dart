import '../../../core/utils/bike_id.dart';

class Trip {
  const Trip({
    required this.id,
    required this.externalId,
    required this.userId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.startedAt,
    required this.durationSeconds,
    required this.isShared,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.directDistanceMeters,
    this.bikeId,
    this.tripCost,
    this.pitStops = const [],
    this.stageIds = const [],
    this.stageDetails = const [],
    this.parentJourneyId,
    this.parentJourneyOriginStationId,
    this.parentJourneyDestinationStationId,
  });

  final String id;
  final String externalId;
  final String userId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final DateTime startedAt;
  final int durationSeconds;
  final bool isShared;
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final double? directDistanceMeters;
  final String? bikeId;
  final String? tripCost;
  final List<PitStop> pitStops;
  final List<String> stageIds;
  final List<JourneyStageDetails> stageDetails;
  final String? parentJourneyId;
  final String? parentJourneyOriginStationId;
  final String? parentJourneyDestinationStationId;

  bool get hasPitStops => pitStops.isNotEmpty;

  bool get isJourneyProjection => parentJourneyId != null;

  String get navigationJourneyId => parentJourneyId ?? id;

  String get navigationOriginStationId =>
      parentJourneyOriginStationId ?? originStationId;

  String get navigationDestinationStationId =>
      parentJourneyDestinationStationId ?? destinationStationId;

  int get stageCount => stageIds.isEmpty ? 1 : stageIds.length;

  List<String> get bikeIds {
    final values = stageDetails.isEmpty
        ? [bikeId]
        : [for (final stage in stageDetails) stage.bikeId];
    return values
        .map(normalizeBikeId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  bool get hasMultipleBikes => bikeIds.length > 1;

  bool get hasCompleteBikeData => stageDetails.isEmpty
      ? bikeId != null
      : stageDetails.every((stage) => stage.bikeId != null);

  DateTime get endedAt => startedAt.add(Duration(seconds: durationSeconds));

  double? get equivalentAverageSpeedKmh {
    final distance = directDistanceMeters;
    if (distance == null || durationSeconds <= 0) {
      return null;
    }
    return distance / durationSeconds * 3.6;
  }

  bool matchesRoute({
    required String originStationId,
    required String destinationStationId,
  }) {
    return this.originStationId == originStationId &&
        this.destinationStationId == destinationStationId;
  }

  Trip copyWith({
    String? id,
    String? externalId,
    String? userId,
    String? originStationId,
    String? originStationName,
    String? destinationStationId,
    String? destinationStationName,
    DateTime? startedAt,
    int? durationSeconds,
    bool? isShared,
    double? originLatitude,
    double? originLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    double? directDistanceMeters,
    String? bikeId,
    String? tripCost,
    List<PitStop>? pitStops,
    List<String>? stageIds,
    List<JourneyStageDetails>? stageDetails,
    String? parentJourneyId,
    String? parentJourneyOriginStationId,
    String? parentJourneyDestinationStationId,
  }) {
    return Trip(
      id: id ?? this.id,
      externalId: externalId ?? this.externalId,
      userId: userId ?? this.userId,
      originStationId: originStationId ?? this.originStationId,
      originStationName: originStationName ?? this.originStationName,
      destinationStationId: destinationStationId ?? this.destinationStationId,
      destinationStationName:
          destinationStationName ?? this.destinationStationName,
      startedAt: startedAt ?? this.startedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isShared: isShared ?? this.isShared,
      originLatitude: originLatitude ?? this.originLatitude,
      originLongitude: originLongitude ?? this.originLongitude,
      destinationLatitude: destinationLatitude ?? this.destinationLatitude,
      destinationLongitude: destinationLongitude ?? this.destinationLongitude,
      directDistanceMeters: directDistanceMeters ?? this.directDistanceMeters,
      bikeId: bikeId ?? this.bikeId,
      tripCost: tripCost ?? this.tripCost,
      pitStops: pitStops ?? this.pitStops,
      stageIds: stageIds ?? this.stageIds,
      stageDetails: stageDetails ?? this.stageDetails,
      parentJourneyId: parentJourneyId ?? this.parentJourneyId,
      parentJourneyOriginStationId:
          parentJourneyOriginStationId ?? this.parentJourneyOriginStationId,
      parentJourneyDestinationStationId:
          parentJourneyDestinationStationId ??
          this.parentJourneyDestinationStationId,
    );
  }
}

class JourneyStageDetails {
  const JourneyStageDetails({
    required this.stageId,
    required this.sourceTripId,
    required this.bikeId,
    required this.tripCost,
  });

  factory JourneyStageDetails.fromTrip(Trip trip) {
    return JourneyStageDetails(
      stageId: trip.id,
      sourceTripId: trip.externalId,
      bikeId: trip.bikeId,
      tripCost: trip.tripCost,
    );
  }

  final String stageId;
  final String sourceTripId;
  final String? bikeId;
  final String? tripCost;

  Map<String, Object?> toJson() => {
    'stageId': stageId,
    'sourceTripId': sourceTripId,
    'bikeId': bikeId,
    'tripCost': tripCost,
  };

  static JourneyStageDetails? fromJson(Map<String, Object?> json) {
    final stageId = json['stageId'];
    final sourceTripId = json['sourceTripId'];
    if (stageId is! String || sourceTripId is! String) {
      return null;
    }
    return JourneyStageDetails(
      stageId: stageId,
      sourceTripId: sourceTripId,
      bikeId: normalizeBikeId(json['bikeId']),
      tripCost: json['tripCost'] as String?,
    );
  }
}

class PitStop {
  const PitStop({
    required this.stationId,
    required this.stationName,
    required this.durationSeconds,
    this.latitude,
    this.longitude,
  });

  final String stationId;
  final String stationName;
  final int durationSeconds;
  final double? latitude;
  final double? longitude;

  PitStop copyWith({double? latitude, double? longitude}) {
    return PitStop(
      stationId: stationId,
      stationName: stationName,
      durationSeconds: durationSeconds,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'durationSeconds': durationSeconds,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  static PitStop? fromJson(Map<String, Object?> json) {
    final stationId = json['stationId'];
    final stationName = json['stationName'];
    final durationSeconds = json['durationSeconds'];
    if (stationId is! String ||
        stationName is! String ||
        durationSeconds is! int) {
      return null;
    }
    return PitStop(
      stationId: stationId,
      stationName: stationName,
      durationSeconds: durationSeconds,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
