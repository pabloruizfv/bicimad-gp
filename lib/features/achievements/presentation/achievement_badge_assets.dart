import '../domain/achievement.dart';

String baseAchievementBadgeAssetPath(AchievementLevelId? level) =>
    switch (level) {
      null => 'assets/badges/level_markers/badge_level_locked.svg',
      AchievementLevelId.graphite =>
        'assets/badges/level_markers/badge_level_graphite.svg',
      AchievementLevelId.bronze =>
        'assets/badges/level_markers/badge_level_bronze.svg',
      AchievementLevelId.silver =>
        'assets/badges/level_markers/badge_level_silver.svg',
      AchievementLevelId.gold =>
        'assets/badges/level_markers/badge_level_gold.svg',
    };
