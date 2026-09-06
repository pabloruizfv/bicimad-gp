import 'package:bicimad_social/features/achievements/domain/achievement.dart';
import 'package:bicimad_social/features/achievements/domain/achievement_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resuelve el tier desde los umbrales de la categoría', () {
    expect(pitStopsAchievement.levelForProgress(0), isNull);
    expect(
      pitStopsAchievement.levelForProgress(8)?.id,
      AchievementLevelId.graphite,
    );
    expect(
      pitStopsAchievement.levelForProgress(25)?.id,
      AchievementLevelId.bronze,
    );
    expect(
      pitStopsAchievement.levelForProgress(74)?.id,
      AchievementLevelId.silver,
    );
    expect(
      pitStopsAchievement.levelForProgress(180)?.id,
      AchievementLevelId.gold,
    );
  });

  test('preview lejano combina top 3, discontinuidad y entorno', () {
    final ranking = _ranking(total: 12, currentRank: 10);

    expect(
      ranking.previewItems().map(
        (item) => item.isGap ? 'gap' : item.entry!.rank,
      ),
      [1, 2, 3, 'gap', 9, 10, 11],
    );
    expect(ranking.currentUserTopPercent, 84);
  });

  test('preview cercano no repite filas ni añade discontinuidad absurda', () {
    final ranking = _ranking(total: 6, currentRank: 4);

    expect(ranking.previewItems().map((item) => item.entry?.rank), [
      1,
      2,
      3,
      4,
      5,
    ]);
  });

  test('preview pequeño solo muestra los usuarios existentes', () {
    final ranking = _ranking(total: 2, currentRank: 2);

    expect(ranking.previewItems().map((item) => item.entry?.rank), [1, 2]);
  });

  test('preview del último incluye al anterior y omite posterior', () {
    final ranking = _ranking(total: 10, currentRank: 10);

    expect(
      ranking.previewItems().map(
        (item) => item.isGap ? 'gap' : item.entry!.rank,
      ),
      [1, 2, 3, 'gap', 9, 10],
    );
  });

  test('sin usuario actual solo muestra el top 3', () {
    final ranking = _ranking(total: 8, currentRank: null);

    expect(ranking.previewItems().map((item) => item.entry?.rank), [1, 2, 3]);
    expect(ranking.currentUserTopPercent, isNull);
  });

  test('el porcentaje superior nunca muestra Top 0', () {
    final ranking = _ranking(total: 1000, currentRank: 1);

    expect(ranking.currentUserTopPercent, 1);
  });
}

AchievementCommunityRanking _ranking({
  required int total,
  required int? currentRank,
}) {
  return AchievementCommunityRanking(
    categoryId: pitStopsAchievement.id,
    totalUsers: total,
    entries: [
      for (var rank = 1; rank <= total; rank++)
        AchievementRankingEntry(
          rank: rank,
          userId: 'user-$rank',
          displayName: 'Usuario $rank',
          avatarKey: '${rank % 4 + 1}.png',
          value: total - rank,
          isCurrentUser: rank == currentRank,
        ),
    ],
  );
}
