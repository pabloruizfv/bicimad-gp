import '../../trips/domain/trip.dart';
import '../../trips/domain/station_code.dart';
import 'achievement.dart';

class AchievementService {
  const AchievementService();

  List<AchievementProgress> evaluate({
    required List<Trip> journeys,
    List<Trip>? routeJourneys,
    Iterable<UserAchievement> persisted = const [],
  }) {
    final routes = routeJourneys ?? journeys;
    return [
      for (final definition in achievementCatalog)
        _evaluateCategory(definition, journeys, routes, persisted),
    ];
  }

  List<AchievementSummary> summaries(Iterable<UserAchievement> achievements) {
    final byCategory = <String, List<UserAchievement>>{};
    for (final achievement in achievements) {
      byCategory.putIfAbsent(achievement.categoryId, () => []).add(achievement);
    }
    return [
      for (final definition in achievementCatalog)
        _summaryFor(definition, byCategory[definition.id] ?? const []),
    ];
  }

  AchievementSummary _summaryFor(
    AchievementCategoryDefinition definition,
    List<UserAchievement> achievements,
  ) {
    var progress = 0;
    for (final achievement in achievements) {
      if (achievement.progress > progress) {
        progress = achievement.progress;
      }
    }
    return AchievementSummary(
      definition: definition,
      currentLevel: _highestDefinition(definition, achievements),
      progress: progress,
    );
  }

  AchievementProgress _evaluateCategory(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    List<Trip> routeJourneys,
    Iterable<UserAchievement> persisted,
  ) {
    return switch (definition.rule) {
      AchievementProgressRule.pitStops => _evaluatePitStops(
        definition,
        journeys,
        persisted,
      ),
      AchievementProgressRule.fastTrips => _evaluateFastTrips(
        definition,
        journeys,
        persisted,
      ),
      AchievementProgressRule.longTrips => _evaluateLongTrips(
        definition,
        journeys,
        persisted,
      ),
      AchievementProgressRule.stationUsage => _evaluateStationUsage(
        definition,
        journeys,
        persisted,
      ),
      AchievementProgressRule.bikeUsage => _evaluateBikeUsage(
        definition,
        journeys,
        persisted,
      ),
      AchievementProgressRule.nightTrips => _evaluateJourneyContributions(
        definition,
        journeys,
        persisted,
        contribution: (journey) => journey.startedAt.toLocal().hour < 6 ? 1 : 0,
      ),
      AchievementProgressRule.exploredRoutes => _evaluateExploredRoutes(
        definition,
        routeJourneys,
        persisted,
      ),
    };
  }

  AchievementProgress _evaluateExploredRoutes(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted,
  ) {
    final chronological = [...journeys]
      ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    final seen = <String>{};
    final unlocks = <AchievementLevelId, DateTime>{};
    var progress = 0;
    for (final journey in chronological) {
      final origin = _stationKey(
        journey.originStationId,
        journey.originStationName,
      );
      final destination = _stationKey(
        journey.destinationStationId,
        journey.destinationStationName,
      );
      if (origin == null || destination == null || origin == destination) {
        continue;
      }
      if (!seen.add('$origin\u0000$destination')) {
        continue;
      }
      final previous = progress++;
      for (final level in definition.levels) {
        if (previous < level.threshold && progress >= level.threshold) {
          unlocks[level.id] = journey.endedAt;
        }
      }
    }
    _mergePersisted(
      definition: definition,
      persisted: persisted,
      unlocks: unlocks,
      onHigherProgress: (value) => progress = value,
      currentProgress: () => progress,
    );
    return AchievementProgress(
      definition: definition,
      progress: progress,
      unlocks: Map.unmodifiable(unlocks),
      relatedJourneys: List.unmodifiable(journeys),
      allJourneys: List.unmodifiable(journeys),
    );
  }

  AchievementProgress _evaluatePitStops(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted,
  ) {
    return _evaluateJourneyContributions(
      definition,
      journeys,
      persisted,
      contribution: (journey) => journey.pitStops.length,
    );
  }

  AchievementProgress _evaluateFastTrips(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted,
  ) {
    return _evaluateJourneyContributions(
      definition,
      journeys,
      persisted,
      contribution: (journey) {
        final speed = journey.equivalentAverageSpeedKmh;
        return speed != null &&
                speed >
                    fastTripSpeedThresholdKmh + fastTripSpeedComparisonEpsilon
            ? 1
            : 0;
      },
    );
  }

  AchievementProgress _evaluateLongTrips(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted,
  ) {
    return _evaluateJourneyContributions(
      definition,
      journeys,
      persisted,
      contribution: (journey) {
        final distance = journey.directDistanceMeters;
        return distance != null && distance > longTripDistanceThresholdMeters
            ? 1
            : 0;
      },
    );
  }

  AchievementProgress _evaluateStationUsage(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted,
  ) {
    final chronological = [...journeys]
      ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    final counts = <String, int>{};
    final unlocks = <AchievementLevelId, DateTime>{};
    var progress = 0;

    for (final journey in chronological) {
      final stationKeys = [
        _stationKey(journey.originStationId, journey.originStationName),
        _stationKey(
          journey.destinationStationId,
          journey.destinationStationName,
        ),
      ];
      final previous = progress;
      for (final key in stationKeys.whereType<String>()) {
        final uses = (counts[key] ?? 0) + 1;
        counts[key] = uses;
        if (uses > progress) {
          progress = uses;
        }
      }
      for (final level in definition.levels) {
        if (previous < level.threshold && progress >= level.threshold) {
          unlocks[level.id] = journey.endedAt;
        }
      }
    }

    _mergePersisted(
      definition: definition,
      persisted: persisted,
      unlocks: unlocks,
      onHigherProgress: (value) => progress = value,
      currentProgress: () => progress,
    );

    final mostUsedKeys = counts.entries
        .where((entry) => entry.value == progress)
        .map((entry) => entry.key)
        .toSet();
    return AchievementProgress(
      definition: definition,
      progress: progress,
      unlocks: Map.unmodifiable(unlocks),
      relatedJourneys: List.unmodifiable(
        journeys.where((journey) {
          final origin = _stationKey(
            journey.originStationId,
            journey.originStationName,
          );
          final destination = _stationKey(
            journey.destinationStationId,
            journey.destinationStationName,
          );
          return mostUsedKeys.contains(origin) ||
              mostUsedKeys.contains(destination);
        }),
      ),
      allJourneys: List.unmodifiable(journeys),
    );
  }

  AchievementProgress _evaluateBikeUsage(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted,
  ) {
    final chronological = [...journeys]
      ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    final counts = <String, int>{};
    final unlocks = <AchievementLevelId, DateTime>{};
    var progress = 0;

    for (final journey in chronological) {
      final previous = progress;
      for (final bikeId in journey.bikeIds.toSet()) {
        final uses = (counts[bikeId] ?? 0) + 1;
        counts[bikeId] = uses;
        if (uses > progress) {
          progress = uses;
        }
      }
      for (final level in definition.levels) {
        if (previous < level.threshold && progress >= level.threshold) {
          unlocks[level.id] = journey.endedAt;
        }
      }
    }

    _mergePersisted(
      definition: definition,
      persisted: persisted,
      unlocks: unlocks,
      onHigherProgress: (value) => progress = value,
      currentProgress: () => progress,
    );

    final mostUsedBikeIds =
        counts.entries
            .where((entry) => entry.value == progress)
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort(_compareBikeIds);
    final mostUsedBikeIdSet = mostUsedBikeIds.toSet();
    return AchievementProgress(
      definition: definition,
      progress: progress,
      unlocks: Map.unmodifiable(unlocks),
      relatedJourneys: List.unmodifiable(
        journeys.where(
          (journey) => journey.bikeIds.any(mostUsedBikeIdSet.contains),
        ),
      ),
      allJourneys: List.unmodifiable(journeys),
      relatedBikeIds: List.unmodifiable(mostUsedBikeIds),
    );
  }

  AchievementProgress _evaluateJourneyContributions(
    AchievementCategoryDefinition definition,
    List<Trip> journeys,
    Iterable<UserAchievement> persisted, {
    required int Function(Trip journey) contribution,
  }) {
    final chronological = [...journeys]
      ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    final unlocks = <AchievementLevelId, DateTime>{};
    var progress = 0;
    for (final journey in chronological) {
      final increment = contribution(journey);
      if (increment <= 0) {
        continue;
      }
      final previous = progress;
      progress += increment;
      for (final level in definition.levels) {
        if (previous < level.threshold && progress >= level.threshold) {
          unlocks[level.id] = journey.endedAt;
        }
      }
    }

    for (final achievement in persisted) {
      if (achievement.categoryId != definition.id ||
          !definition.levels.any((level) => level.id == achievement.levelId)) {
        continue;
      }
      final existing = unlocks[achievement.levelId];
      if (existing == null || achievement.unlockedAt.isBefore(existing)) {
        unlocks[achievement.levelId] = achievement.unlockedAt;
      }
      if (achievement.progress > progress) {
        progress = achievement.progress;
      }
    }

    return AchievementProgress(
      definition: definition,
      progress: progress,
      unlocks: Map.unmodifiable(unlocks),
      relatedJourneys: List.unmodifiable(
        journeys.where((journey) => contribution(journey) > 0),
      ),
      allJourneys: List.unmodifiable(journeys),
    );
  }

  AchievementLevelDefinition? _highestDefinition(
    AchievementCategoryDefinition definition,
    List<UserAchievement> achievements,
  ) {
    AchievementLevelDefinition? result;
    for (final level in definition.levels) {
      if (achievements.any((achievement) => achievement.levelId == level.id)) {
        result = level;
      }
    }
    return result;
  }

  void _mergePersisted({
    required AchievementCategoryDefinition definition,
    required Iterable<UserAchievement> persisted,
    required Map<AchievementLevelId, DateTime> unlocks,
    required int Function() currentProgress,
    required void Function(int value) onHigherProgress,
  }) {
    for (final achievement in persisted) {
      if (achievement.categoryId != definition.id ||
          !definition.levels.any((level) => level.id == achievement.levelId)) {
        continue;
      }
      final existing = unlocks[achievement.levelId];
      if (existing == null || achievement.unlockedAt.isBefore(existing)) {
        unlocks[achievement.levelId] = achievement.unlockedAt;
      }
      if (achievement.progress > currentProgress()) {
        onHigherProgress(achievement.progress);
      }
    }
  }
}

int _compareBikeIds(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  return left.compareTo(right);
}

String? _stationKey(String stationId, String stationName) {
  final publicCode = canonicalStationCode(
    stationId: stationId,
    stationName: stationName,
  );
  if (publicCode != null) {
    return publicCode;
  }
  final id = stationId.trim().toLowerCase();
  return id.isEmpty ? null : 'id:$id';
}
