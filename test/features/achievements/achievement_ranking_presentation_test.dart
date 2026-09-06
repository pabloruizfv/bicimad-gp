import 'dart:async';

import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/achievements/domain/achievement.dart';
import 'package:bicimad_social/features/achievements/domain/achievement_ranking.dart';
import 'package:bicimad_social/features/achievements/presentation/achievement_ranking_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra top 3, entorno, resumen y tiers base', (tester) async {
    final ranking = _ranking(total: 12, currentRank: 10);
    await tester.pumpWidget(_appWithRanking(ranking));
    await tester.pumpAndSettle();

    for (final rank in [1, 2, 3, 9, 10, 11]) {
      expect(
        find.byKey(ValueKey('achievement-ranking-row-user-$rank')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('achievement-ranking-row-user-4')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('achievement-ranking-gap')),
      findsOneWidget,
    );
    expect(find.text('#10 · Top 84 %'), findsOneWidget);
    expect(find.text('Tú'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('achievement-ranking-tier-user-1-gold')),
      findsOneWidget,
    );

    final currentMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('achievement-ranking-row-user-10')),
    );
    expect(currentMaterial.color, isNot(Colors.transparent));
  });

  testWidgets('valor cero usa el emblema base bloqueado', (tester) async {
    final ranking = AchievementCommunityRanking(
      categoryId: pitStopsAchievement.id,
      totalUsers: 1,
      entries: const [
        AchievementRankingEntry(
          rank: 1,
          userId: 'current',
          displayName: 'Usuario',
          avatarKey: '1.png',
          value: 0,
          isCurrentUser: true,
        ),
      ],
    );
    await tester.pumpWidget(_appWithRanking(ranking));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('achievement-ranking-tier-current-locked')),
      findsOneWidget,
    );
  });

  testWidgets('Ver todo abre el ranking completo con las mismas filas', (
    tester,
  ) async {
    final ranking = _ranking(total: 12, currentRank: 10);
    await tester.pumpWidget(_appWithRanking(ranking));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver todo'));
    await tester.pumpAndSettle();

    expect(find.text('Pit stops · Ranking'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('achievement-full-ranking-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('achievement-ranking-row-user-1')),
      findsOneWidget,
    );
  });

  testWidgets('mantiene estados de carga, error y vacío discretos', (
    tester,
  ) async {
    final pending = Completer<AchievementCommunityRanking>();
    await tester.pumpWidget(_rankingApp((ref, categoryId) => pending.future));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('achievement-ranking-loading')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _rankingApp((ref, categoryId) => Future.error(StateError('offline'))),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('achievement-ranking-error')),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _appWithRanking(
        AchievementCommunityRanking(
          categoryId: pitStopsAchievement.id,
          entries: const [],
          totalUsers: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('achievement-ranking-empty')),
      findsOneWidget,
    );
  });
}

Widget _appWithRanking(AchievementCommunityRanking ranking) {
  return _rankingApp((ref, categoryId) async => ranking);
}

Widget _rankingApp(
  Future<AchievementCommunityRanking> Function(Ref ref, String categoryId)
  loader,
) {
  return ProviderScope(
    overrides: [achievementRankingProvider.overrideWith(loader)],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(12),
          child: AchievementCommunityRankingSection(
            definition: pitStopsAchievement,
          ),
        ),
      ),
    ),
  );
}

AchievementCommunityRanking _ranking({
  required int total,
  required int currentRank,
}) {
  return AchievementCommunityRanking(
    categoryId: pitStopsAchievement.id,
    totalUsers: total,
    entries: [
      for (var rank = 1; rank <= total; rank++)
        AchievementRankingEntry(
          rank: rank,
          userId: 'user-$rank',
          displayName: 'Usuario con nombre largo $rank',
          avatarKey: '${rank % 4 + 1}.png',
          value: 120 - rank * 10,
          isCurrentUser: rank == currentRank,
        ),
    ],
  );
}
