import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../domain/achievement.dart';

class AchievementBadgeViewData {
  const AchievementBadgeViewData({
    required this.definition,
    required this.level,
    required this.assetPath,
    this.progress,
  });

  factory AchievementBadgeViewData.fromProgress(AchievementProgress progress) {
    return AchievementBadgeViewData(
      definition: progress.definition,
      level: progress.currentLevel,
      assetPath: progress.visibleAssetPath,
      progress: progress.progress,
    );
  }

  factory AchievementBadgeViewData.fromSummary(AchievementSummary summary) {
    return AchievementBadgeViewData(
      definition: summary.definition,
      level: summary.currentLevel,
      assetPath: summary.visibleAssetPath,
      progress: summary.progress,
    );
  }

  final AchievementCategoryDefinition definition;
  final AchievementLevelDefinition? level;
  final String assetPath;
  final int? progress;

  int get earnedLevelCount {
    final currentLevel = level;
    if (currentLevel == null) {
      return 0;
    }
    final index = definition.levels.indexWhere(
      (candidate) => candidate.id == currentLevel.id,
    );
    return index < 0 ? 0 : index + 1;
  }

  double get progressWithinLevel {
    final currentLevel = level;
    final currentProgress = progress;
    if (currentLevel == null || currentProgress == null) {
      return 0;
    }
    final currentIndex = definition.levels.indexWhere(
      (candidate) => candidate.id == currentLevel.id,
    );
    if (currentIndex < 0) {
      return 0;
    }
    if (currentIndex == definition.levels.length - 1) {
      return ((currentProgress - currentLevel.threshold) /
              currentLevel.threshold)
          .clamp(0, double.infinity)
          .toDouble();
    }
    final nextLevel = definition.levels[currentIndex + 1];
    final interval = nextLevel.threshold - currentLevel.threshold;
    if (interval <= 0) {
      return 0;
    }
    return ((currentProgress - currentLevel.threshold) / interval)
        .clamp(0, 1)
        .toDouble();
  }

  int get visibleProgress => progress ?? level?.threshold ?? 0;
}

class AchievementShowcase extends StatelessWidget {
  const AchievementShowcase({
    required this.badges,
    required this.onBadgeTap,
    super.key,
  });

  final List<AchievementBadgeViewData> badges;
  final ValueChanged<int> onBadgeTap;

  @override
  Widget build(BuildContext context) {
    final orderedBadges =
        [
          for (var index = 0; index < badges.length; index++)
            if (badges[index].earnedLevelCount > 0)
              (index: index, badge: badges[index]),
        ]..sort((left, right) {
          final levelComparison = right.badge.earnedLevelCount.compareTo(
            left.badge.earnedLevelCount,
          );
          if (levelComparison != 0) {
            return levelComparison;
          }
          final progressComparison = right.badge.progressWithinLevel.compareTo(
            left.badge.progressWithinLevel,
          );
          return progressComparison != 0
              ? progressComparison
              : left.index.compareTo(right.index);
        });
    final earnedLevels = badges.fold<int>(
      0,
      (total, badge) => total + badge.earnedLevelCount,
    );
    final totalLevels = badges.fold<int>(
      0,
      (total, badge) => total + badge.definition.levels.length,
    );
    return Card(
      key: const ValueKey('achievement-showcase'),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Insignias',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('achievement-level-counter'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$earnedLevels/$totalLevels',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              key: const ValueKey('achievement-badge-scroll'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in orderedBadges)
                    _AchievementBadge(
                      data: item.badge,
                      onTap: () => onBadgeTap(item.index),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AchievementShowcaseLoading extends StatelessWidget {
  const AchievementShowcaseLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Colors.white,
      child: SizedBox(
        height: 122,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.data, required this.onTap});

  final AchievementBadgeViewData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final levelName = data.level?.id.displayName ?? 'Bloqueado';
    return Semantics(
      button: true,
      label: '${data.definition.name}, $levelName',
      child: InkWell(
        key: ValueKey('achievement-badge-${data.definition.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 72,
          height: 98,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 84,
                child: OverflowBox(
                  minWidth: 86,
                  maxWidth: 86,
                  minHeight: 86,
                  maxHeight: 86,
                  child: SvgPicture.asset(
                    data.assetPath,
                    key: ValueKey('achievement-asset-${data.assetPath}'),
                    width: 86,
                    height: 86,
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -3),
                child: Text(
                  '${data.visibleProgress}',
                  key: ValueKey('achievement-progress-${data.definition.id}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
