import '../../trips/domain/trip.dart';

enum AchievementLevelId { graphite, bronze, silver, gold }

extension AchievementLevelIdValues on AchievementLevelId {
  String get wireName => name;

  String get displayName => switch (this) {
    AchievementLevelId.graphite => 'Grafito',
    AchievementLevelId.bronze => 'Bronce',
    AchievementLevelId.silver => 'Plata',
    AchievementLevelId.gold => 'Oro',
  };

  static AchievementLevelId? parse(Object? value) {
    final name = value?.toString();
    for (final level in AchievementLevelId.values) {
      if (level.name == name) {
        return level;
      }
    }
    return null;
  }
}

class AchievementLevelDefinition {
  const AchievementLevelDefinition({
    required this.id,
    required this.threshold,
    required this.assetPath,
  });

  final AchievementLevelId id;
  final int threshold;
  final String assetPath;
}

enum AchievementProgressRule {
  pitStops,
  fastTrips,
  longTrips,
  stationUsage,
  bikeUsage,
}

const fastTripSpeedThresholdKmh = 14.0;
const fastTripSpeedComparisonEpsilon = 1e-9;
const longTripDistanceThresholdMeters = 5000.0;

class AchievementCategoryDefinition {
  const AchievementCategoryDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.requirementUnitSingular,
    required this.requirementUnit,
    required this.lockedAssetPath,
    required this.rule,
    required this.levels,
  });

  final String id;
  final String name;
  final String description;
  final String requirementUnitSingular;
  final String requirementUnit;
  final String lockedAssetPath;
  final AchievementProgressRule rule;
  final List<AchievementLevelDefinition> levels;

  String formatProgress(int value) {
    return '$value '
        '${value == 1 ? requirementUnitSingular : requirementUnit}';
  }

  AchievementLevelDefinition? levelForProgress(int progress) {
    AchievementLevelDefinition? result;
    for (final level in levels) {
      if (progress >= level.threshold) {
        result = level;
      }
    }
    return result;
  }
}

const pitStopsAchievement = AchievementCategoryDefinition(
  id: 'pit_stops',
  name: 'Pit stops',
  description: 'Encadena etapas con una parada intermedia breve.',
  requirementUnitSingular: 'pit stop',
  requirementUnit: 'pit stops',
  lockedAssetPath: 'assets/badges/pit_stops/badge_pit_stop_locked.svg',
  rule: AchievementProgressRule.pitStops,
  levels: [
    AchievementLevelDefinition(
      id: AchievementLevelId.graphite,
      threshold: 1,
      assetPath: 'assets/badges/pit_stops/badge_pit_stop_1_graphite.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.bronze,
      threshold: 10,
      assetPath: 'assets/badges/pit_stops/badge_pit_stop_10_bronze.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.silver,
      threshold: 50,
      assetPath: 'assets/badges/pit_stops/badge_pit_stop_50_silver.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.gold,
      threshold: 100,
      assetPath: 'assets/badges/pit_stops/badge_pit_stop_100_gold.svg',
    ),
  ],
);

const fastTripsAchievement = AchievementCategoryDefinition(
  id: 'fast_trips_14_kmh',
  name: 'Viajes veloces',
  description:
      'Completa viajes con una velocidad media equivalente superior a 14 km/h.',
  requirementUnitSingular: 'viaje veloz',
  requirementUnit: 'viajes veloces',
  lockedAssetPath: 'assets/badges/fast_trips/badge_fast_trip_locked.svg',
  rule: AchievementProgressRule.fastTrips,
  levels: [
    AchievementLevelDefinition(
      id: AchievementLevelId.graphite,
      threshold: 1,
      assetPath: 'assets/badges/fast_trips/badge_fast_trip_1_graphite.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.bronze,
      threshold: 10,
      assetPath: 'assets/badges/fast_trips/badge_fast_trip_10_bronze.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.silver,
      threshold: 50,
      assetPath: 'assets/badges/fast_trips/badge_fast_trip_50_silver.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.gold,
      threshold: 100,
      assetPath: 'assets/badges/fast_trips/badge_fast_trip_100_gold.svg',
    ),
  ],
);

const longTripsAchievement = AchievementCategoryDefinition(
  id: 'long_trips_5_km',
  name: 'Viajes largos',
  description: 'Completa viajes con una distancia directa superior a 5 km.',
  requirementUnitSingular: 'viaje largo',
  requirementUnit: 'viajes largos',
  lockedAssetPath: 'assets/badges/long_trips/badge_long_trip_locked.svg',
  rule: AchievementProgressRule.longTrips,
  levels: [
    AchievementLevelDefinition(
      id: AchievementLevelId.graphite,
      threshold: 1,
      assetPath: 'assets/badges/long_trips/badge_long_trip_1_graphite.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.bronze,
      threshold: 10,
      assetPath: 'assets/badges/long_trips/badge_long_trip_10_bronze.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.silver,
      threshold: 50,
      assetPath: 'assets/badges/long_trips/badge_long_trip_50_silver.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.gold,
      threshold: 100,
      assetPath: 'assets/badges/long_trips/badge_long_trip_100_gold.svg',
    ),
  ],
);

const favoriteStationAchievement = AchievementCategoryDefinition(
  id: 'favorite_station',
  name: 'Estación favorita',
  description:
      'Empieza o termina tus viajes muchas veces en una misma estación.',
  requirementUnitSingular: 'uso de una misma estación',
  requirementUnit: 'usos de una misma estación',
  lockedAssetPath: 'assets/badges/stations/badge_favorite_station_locked.svg',
  rule: AchievementProgressRule.stationUsage,
  levels: [
    AchievementLevelDefinition(
      id: AchievementLevelId.graphite,
      threshold: 10,
      assetPath:
          'assets/badges/stations/badge_favorite_station_10_graphite.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.bronze,
      threshold: 50,
      assetPath: 'assets/badges/stations/badge_favorite_station_50_bronze.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.silver,
      threshold: 200,
      assetPath: 'assets/badges/stations/badge_favorite_station_200_silver.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.gold,
      threshold: 500,
      assetPath: 'assets/badges/stations/badge_favorite_station_500_gold.svg',
    ),
  ],
);

const favoriteBikeAchievement = AchievementCategoryDefinition(
  id: 'favorite_bike',
  name: 'Bici favorita',
  description: 'Usa una misma bicicleta en viajes diferentes.',
  requirementUnitSingular: 'viaje con una misma bici',
  requirementUnit: 'viajes con una misma bici',
  lockedAssetPath: 'assets/badges/bikes/badge_favorite_bike_locked.svg',
  rule: AchievementProgressRule.bikeUsage,
  levels: [
    AchievementLevelDefinition(
      id: AchievementLevelId.graphite,
      threshold: 2,
      assetPath: 'assets/badges/bikes/badge_favorite_bike_2_graphite.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.bronze,
      threshold: 3,
      assetPath: 'assets/badges/bikes/badge_favorite_bike_3_bronze.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.silver,
      threshold: 4,
      assetPath: 'assets/badges/bikes/badge_favorite_bike_4_silver.svg',
    ),
    AchievementLevelDefinition(
      id: AchievementLevelId.gold,
      threshold: 5,
      assetPath: 'assets/badges/bikes/badge_favorite_bike_5_gold.svg',
    ),
  ],
);

const achievementCatalog = [
  pitStopsAchievement,
  fastTripsAchievement,
  longTripsAchievement,
  favoriteStationAchievement,
  favoriteBikeAchievement,
];

class UserAchievement {
  const UserAchievement({
    required this.categoryId,
    required this.levelId,
    required this.threshold,
    required this.unlockedAt,
    int? progress,
  }) : progress = progress ?? threshold;

  final String categoryId;
  final AchievementLevelId levelId;
  final int threshold;
  final DateTime unlockedAt;
  final int progress;

  String get key => '$categoryId:${levelId.name}';
}

class AchievementProgress {
  const AchievementProgress({
    required this.definition,
    required this.progress,
    required this.unlocks,
    required this.relatedJourneys,
    this.allJourneys = const [],
    this.relatedBikeIds = const [],
  });

  final AchievementCategoryDefinition definition;
  final int progress;
  final Map<AchievementLevelId, DateTime> unlocks;
  final List<Trip> relatedJourneys;
  final List<Trip> allJourneys;
  final List<String> relatedBikeIds;

  AchievementLevelDefinition? get currentLevel {
    AchievementLevelDefinition? result;
    for (final level in definition.levels) {
      if (unlocks.containsKey(level.id)) {
        result = level;
      }
    }
    return result;
  }

  AchievementLevelDefinition? get nextLevel {
    for (final level in definition.levels) {
      if (!unlocks.containsKey(level.id)) {
        return level;
      }
    }
    return null;
  }

  int get remainingForNext {
    final next = nextLevel;
    return next == null
        ? 0
        : (next.threshold - progress).clamp(0, next.threshold);
  }

  String get visibleAssetPath =>
      currentLevel?.assetPath ?? definition.lockedAssetPath;
}

class AchievementSummary {
  const AchievementSummary({
    required this.definition,
    required this.currentLevel,
    required this.progress,
  });

  final AchievementCategoryDefinition definition;
  final AchievementLevelDefinition? currentLevel;
  final int progress;

  String get visibleAssetPath =>
      currentLevel?.assetPath ?? definition.lockedAssetPath;

  String get requirement {
    final level = currentLevel ?? definition.levels.first;
    return definition.formatProgress(level.threshold);
  }
}
