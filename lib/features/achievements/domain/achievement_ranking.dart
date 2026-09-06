import 'achievement.dart';

class AchievementRankingEntry {
  const AchievementRankingEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.avatarKey,
    required this.value,
    required this.isCurrentUser,
  });

  final int rank;
  final String userId;
  final String displayName;
  final String avatarKey;
  final int value;
  final bool isCurrentUser;

  String get avatarAsset => 'assets/avatar/$avatarKey';

  AchievementLevelDefinition? levelFor(
    AchievementCategoryDefinition definition,
  ) => definition.levelForProgress(value);
}

class AchievementCommunityRanking {
  const AchievementCommunityRanking({
    required this.categoryId,
    required this.entries,
    required this.totalUsers,
  });

  final String categoryId;
  final List<AchievementRankingEntry> entries;
  final int totalUsers;

  AchievementRankingEntry? get currentUserEntry {
    for (final entry in entries) {
      if (entry.isCurrentUser) {
        return entry;
      }
    }
    return null;
  }

  int? get currentUserTopPercent {
    final rank = currentUserEntry?.rank;
    if (rank == null || rank <= 0 || totalUsers <= 0) {
      return null;
    }
    return (rank * 100 / totalUsers).ceil().clamp(1, 100);
  }

  List<AchievementRankingPreviewItem> previewItems() {
    if (entries.isEmpty) {
      return const [];
    }
    final indexes = <int>{
      for (var index = 0; index < entries.length && index < 3; index++) index,
    };
    final currentIndex = entries.indexWhere((entry) => entry.isCurrentUser);
    if (currentIndex >= 0) {
      for (var index = currentIndex - 1; index <= currentIndex + 1; index++) {
        if (index >= 0 && index < entries.length) {
          indexes.add(index);
        }
      }
    }
    final sortedIndexes = indexes.toList()..sort();
    final result = <AchievementRankingPreviewItem>[];
    int? previousIndex;
    for (final index in sortedIndexes) {
      if (previousIndex != null && index > previousIndex + 1) {
        result.add(const AchievementRankingPreviewItem.gap());
      }
      result.add(AchievementRankingPreviewItem.entry(entries[index]));
      previousIndex = index;
    }
    return List.unmodifiable(result);
  }
}

class AchievementRankingPreviewItem {
  const AchievementRankingPreviewItem.entry(this.entry) : isGap = false;

  const AchievementRankingPreviewItem.gap() : entry = null, isGap = true;

  final AchievementRankingEntry? entry;
  final bool isGap;
}
