import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/achievements/domain/achievement.dart';
import 'package:bicimad_social/features/achievements/domain/achievement_ranking.dart';
import 'package:bicimad_social/features/achievements/domain/achievement_service.dart';
import 'package:bicimad_social/features/achievements/presentation/achievement_detail_screen.dart';
import 'package:bicimad_social/features/achievements/presentation/achievement_showcase.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/presentation/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la tira oculta las insignias bloqueadas', (tester) async {
    final progress = const AchievementService().evaluate(journeys: const []);
    final pitStops = progress.firstWhere(
      (item) => item.definition.id == pitStopsAchievement.id,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementShowcase(
            badges: [AchievementBadgeViewData.fromProgress(pitStops)],
            onBadgeTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('achievement-badge-pit_stops')),
      findsNothing,
    );
    expect(
      find.byKey(
        ValueKey('achievement-asset-${pitStopsAchievement.lockedAssetPath}'),
      ),
      findsNothing,
    );
    expect(find.text('Insignias'), findsOneWidget);
    expect(find.text('0/4'), findsOneWidget);
    expect(find.text('Pit stops'), findsNothing);
  });

  testWidgets('el SVG productivo del emblema se carga desde assets', (
    tester,
  ) async {
    final assetPaths = [
      pitStopsAchievement.lockedAssetPath,
      favoriteStationAchievement.levels.first.assetPath,
    ];
    for (final assetPath in assetPaths) {
      final source = await rootBundle.loadString(assetPath);
      expect(source, contains('viewBox="0 0 512 512"'));
      expect(source, contains('id="badge-content"'));
    }
    for (final metal in AchievementLevelId.values) {
      final source = await rootBundle.loadString(switch (metal) {
        AchievementLevelId.graphite =>
          'assets/badges/level_markers/badge_level_graphite.svg',
        AchievementLevelId.bronze =>
          'assets/badges/level_markers/badge_level_bronze.svg',
        AchievementLevelId.silver =>
          'assets/badges/level_markers/badge_level_silver.svg',
        AchievementLevelId.gold =>
          'assets/badges/level_markers/badge_level_gold.svg',
      });
      expect(source, contains('<g id="badge-content"></g>'));
      expect(source, isNot(contains('<filter')));
      expect(source, isNot(contains('filter="url(')));
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SvgPicture.asset(
            favoriteStationAchievement.levels.first.assetPath,
            width: 100,
            height: 100,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la tira ordena por metal y mantiene el callback original', (
    tester,
  ) async {
    final pitStopLevel = pitStopsAchievement.levels[1];
    final fastLevel = fastTripsAchievement.levels[3];
    int? tappedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementShowcase(
            badges: [
              AchievementBadgeViewData(
                definition: pitStopsAchievement,
                level: pitStopLevel,
                assetPath: pitStopLevel.assetPath,
                progress: 14,
              ),
              AchievementBadgeViewData(
                definition: fastTripsAchievement,
                level: fastLevel,
                assetPath: fastLevel.assetPath,
                progress: 123,
              ),
            ],
            onBadgeTap: (index) => tappedIndex = index,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('achievement-badge-pit_stops')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('achievement-badge-fast_trips_14_kmh')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('achievement-asset-${fastLevel.assetPath}')),
      findsOneWidget,
    );
    expect(find.text('6/8'), findsOneWidget);
    expect(find.text('Pit stops'), findsNothing);
    expect(find.text('Viajes veloces'), findsNothing);
    expect(
      find.byKey(const ValueKey('achievement-progress-pit_stops')),
      findsOneWidget,
    );
    expect(find.text('14'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);

    final fastBadge = find.byKey(
      const ValueKey('achievement-badge-fast_trips_14_kmh'),
    );
    final pitStopBadge = find.byKey(
      const ValueKey('achievement-badge-pit_stops'),
    );
    final fastCenter = tester.getCenter(fastBadge);
    final pitStopCenter = tester.getCenter(pitStopBadge);
    expect(fastCenter.dx, lessThan(pitStopCenter.dx));
    expect(pitStopCenter.dx - fastCenter.dx, lessThan(80));

    await tester.tap(fastBadge);
    expect(tappedIndex, 1);
  });

  testWidgets('las insignias ocupan una fila con scroll horizontal', (
    tester,
  ) async {
    final definitions = achievementCatalog;
    await tester.binding.setSurfaceSize(const Size(260, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementShowcase(
            badges: [
              for (final definition in definitions)
                AchievementBadgeViewData(
                  definition: definition,
                  level: definition.levels.first,
                  assetPath: definition.levels.first.assetPath,
                  progress: definition.levels.first.threshold,
                ),
            ],
            onBadgeTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byKey(const ValueKey('achievement-badge-scroll'));
    final scroll = tester.widget<SingleChildScrollView>(scrollFinder);
    expect(scroll.scrollDirection, Axis.horizontal);

    final firstBadge = find.byKey(
      ValueKey('achievement-badge-${definitions.first.id}'),
    );
    final lastBadge = find.byKey(
      ValueKey('achievement-badge-${definitions.last.id}'),
    );
    expect(tester.getCenter(firstBadge).dy, tester.getCenter(lastBadge).dy);

    await tester.drag(scrollFinder, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(lastBadge).dx, lessThan(260));
  });

  testWidgets('a igual metal ordena por progreso hacia el siguiente nivel', (
    tester,
  ) async {
    final bronzePitStops = pitStopsAchievement.levels[1];
    final bronzeFastTrips = fastTripsAchievement.levels[1];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementShowcase(
            badges: [
              AchievementBadgeViewData(
                definition: fastTripsAchievement,
                level: bronzeFastTrips,
                assetPath: bronzeFastTrips.assetPath,
                progress: 12,
              ),
              AchievementBadgeViewData(
                definition: pitStopsAchievement,
                level: bronzePitStops,
                assetPath: bronzePitStops.assetPath,
                progress: 40,
              ),
            ],
            onBadgeTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pitStopsCenter = tester.getCenter(
      find.byKey(const ValueKey('achievement-badge-pit_stops')),
    );
    final fastTripsCenter = tester.getCenter(
      find.byKey(const ValueKey('achievement-badge-fast_trips_14_kmh')),
    );
    expect(pitStopsCenter.dx, lessThan(fastTripsCenter.dx));
  });

  testWidgets('a igual oro ordena por exceso porcentual sobre el umbral', (
    tester,
  ) async {
    final goldPitStops = pitStopsAchievement.levels.last;
    final goldFastTrips = fastTripsAchievement.levels.last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementShowcase(
            badges: [
              AchievementBadgeViewData(
                definition: fastTripsAchievement,
                level: goldFastTrips,
                assetPath: goldFastTrips.assetPath,
                progress: 110,
              ),
              AchievementBadgeViewData(
                definition: pitStopsAchievement,
                level: goldPitStops,
                assetPath: goldPitStops.assetPath,
                progress: 175,
              ),
            ],
            onBadgeTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pitStopsCenter = tester.getCenter(
      find.byKey(const ValueKey('achievement-badge-pit_stops')),
    );
    final fastTripsCenter = tester.getCenter(
      find.byKey(const ValueKey('achievement-badge-fast_trips_14_kmh')),
    );
    expect(pitStopsCenter.dx, lessThan(fastTripsCenter.dx));
  });

  testWidgets('detalle propio muestra progreso, niveles y journeys', (
    tester,
  ) async {
    final journey = _journeyWithPitStop();
    final progress = const AchievementService()
        .evaluate(journeys: [journey])
        .firstWhere((item) => item.definition.id == pitStopsAchievement.id);
    await tester.pumpWidget(
      _detailApp(OwnAchievementDetailScreen(progress: progress)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pit stops'), findsWidgets);
    expect(find.text('Progreso'), findsOneWidget);
    expect(find.text('1 pit stop'), findsWidgets);
    expect(find.text('Niveles'), findsNothing);
    expect(find.text('Nivel actual'), findsNothing);
    expect(find.textContaining('Faltan'), findsNothing);
    final overview = find.byKey(const ValueKey('achievement-overview-card'));
    expect(overview, findsOneWidget);
    expect(
      find.descendant(of: overview, matching: find.text('Progreso')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.byType(SvgPicture)),
      findsNWidgets(5),
    );
    expect(
      find.byKey(const ValueKey('achievement-progress-track')),
      findsOneWidget,
    );
    for (final level in AchievementLevelId.values) {
      expect(
        find.byKey(ValueKey('achievement-level-marker-${level.name}')),
        findsOneWidget,
      );
    }
    await tester.scrollUntilVisible(
      find.text('Viajes relacionados'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Viajes relacionados'), findsOneWidget);
    expect(
      find.byKey(ValueKey('achievement-journey-${journey.id}')),
      findsOneWidget,
    );
    final tripCard = tester.widget<TripCard>(find.byType(TripCard));
    expect(tripCard.showRoute, isTrue);
    expect(tripCard.avatarAsset, 'assets/avatar/1.png');
    expect(find.text(journey.originStationName), findsOneWidget);
    expect(find.text(journey.destinationStationName), findsOneWidget);
  });

  testWidgets('detalle construye los viajes relacionados de forma perezosa', (
    tester,
  ) async {
    final journeys = [for (var index = 0; index < 500; index++) _trip(index)];
    final progress = AchievementProgress(
      definition: fastTripsAchievement,
      progress: journeys.length,
      unlocks: {
        AchievementLevelId.graphite: journeys.first.endedAt,
        AchievementLevelId.bronze: journeys[9].endedAt,
        AchievementLevelId.silver: journeys[49].endedAt,
        AchievementLevelId.gold: journeys[99].endedAt,
      },
      relatedJourneys: journeys,
      allJourneys: journeys,
    );

    await tester.pumpWidget(
      _detailApp(OwnAchievementDetailScreen(progress: progress)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Viajes relacionados'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('achievement-related-journeys-list')),
      findsOneWidget,
    );
    final initiallyBuiltCards = find.byType(TripCard).evaluate().length;
    expect(initiallyBuiltCards, greaterThan(0));
    expect(initiallyBuiltCards, lessThan(30));
    expect(
      find.byKey(ValueKey('achievement-journey-${journeys.last.id}')),
      findsNothing,
    );
  });

  testWidgets('detalle ajeno solo muestra nombre y requisito', (tester) async {
    const summary = AchievementSummary(
      definition: pitStopsAchievement,
      currentLevel: AchievementLevelDefinition(
        id: AchievementLevelId.bronze,
        threshold: 10,
        assetPath: 'assets/badges/pit_stops/badge_pit_stop_10_bronze.svg',
      ),
      progress: 34,
    );
    await tester.pumpWidget(
      _detailApp(const PublicAchievementDetailScreen(summary: summary)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pit stops'), findsWidgets);
    expect(find.text('Requisito'), findsOneWidget);
    expect(find.text('10 pit stops'), findsOneWidget);
    expect(find.text('Progreso'), findsNothing);
    expect(find.text('Niveles'), findsNothing);
    expect(find.text('Viajes relacionados'), findsNothing);
    expect(find.textContaining('Faltan'), findsNothing);
  });

  testWidgets('detalle propio de velocidad muestra viajes relacionados', (
    tester,
  ) async {
    final journey = _fastJourney();
    final progress = const AchievementService()
        .evaluate(journeys: [journey])
        .firstWhere((item) => item.definition.id == fastTripsAchievement.id);
    await tester.pumpWidget(
      _detailApp(OwnAchievementDetailScreen(progress: progress)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Viajes veloces'), findsWidgets);
    expect(find.text('1 viaje veloz'), findsWidgets);
    expect(
      find.textContaining('velocidad media equivalente superior a 14 km/h'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('achievement-journey-${journey.id}')),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TripCard), findsOneWidget);
    expect(find.textContaining('18.0 km/h'), findsOneWidget);
    expect(find.textContaining('pit stop'), findsNothing);
  });

  testWidgets('detalle ajeno de velocidad solo muestra requisito', (
    tester,
  ) async {
    const summary = AchievementSummary(
      definition: fastTripsAchievement,
      currentLevel: AchievementLevelDefinition(
        id: AchievementLevelId.bronze,
        threshold: 10,
        assetPath: 'assets/badges/fast_trips/badge_fast_trip_10_bronze.svg',
      ),
      progress: 18,
    );
    await tester.pumpWidget(
      _detailApp(const PublicAchievementDetailScreen(summary: summary)),
    );
    await tester.pumpAndSettle();

    expect(find.text('10 viajes veloces'), findsOneWidget);
    expect(find.text('Progreso'), findsNothing);
    expect(find.text('Viajes relacionados'), findsNothing);
  });

  testWidgets('bici favorita permite elegir entre IDs empatados', (
    tester,
  ) async {
    final journeys = [
      _trip(1).copyWith(bikeId: '101'),
      _trip(2).copyWith(bikeId: '202'),
      _trip(3).copyWith(bikeId: '101'),
      _trip(4).copyWith(bikeId: '202'),
    ];
    final progress = const AchievementService()
        .evaluate(journeys: journeys)
        .firstWhere((item) => item.definition.id == favoriteBikeAchievement.id);

    await tester.pumpWidget(
      _detailApp(OwnAchievementDetailScreen(progress: progress)),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('favorite-bike-selector'));
    await tester.scrollUntilVisible(
      selector,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(selector, findsOneWidget);
    expect(find.text('Bicicletas favoritas'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('favorite-bike-dropdown')),
          )
          .value,
      '101',
    );

    await tester.tap(find.byKey(const ValueKey('favorite-bike-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('202').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('favorite-bike-dropdown')),
          )
          .value,
      '202',
    );
    expect(
      find.byKey(const ValueKey('achievement-journey-related-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('achievement-journey-related-2')),
      findsOneWidget,
    );
  });
}

Trip _journeyWithPitStop() {
  return Trip(
    id: 'journey-ab-bc',
    externalId: 'ab+bc',
    userId: 'user',
    originStationId: 'A',
    originStationName: 'A - Origen',
    destinationStationId: 'C',
    destinationStationName: 'C - Destino',
    startedAt: DateTime(2026, 1, 2, 10),
    durationSeconds: 1200,
    isShared: true,
    pitStops: const [
      PitStop(stationId: 'B', stationName: 'B - Parada', durationSeconds: 60),
    ],
  );
}

Widget _detailApp(Widget home) {
  return ProviderScope(
    overrides: [
      achievementRankingProvider.overrideWith((ref, categoryId) async {
        return AchievementCommunityRanking(
          categoryId: categoryId,
          entries: const [],
          totalUsers: 0,
        );
      }),
    ],
    child: MaterialApp(home: home),
  );
}

Trip _fastJourney() {
  return Trip(
    id: 'fast-journey',
    externalId: 'fast-journey',
    userId: 'user',
    originStationId: 'A',
    originStationName: 'A - Origen',
    destinationStationId: 'B',
    destinationStationName: 'B - Destino',
    startedAt: DateTime(2026, 1, 2, 10),
    durationSeconds: 600,
    directDistanceMeters: 3000,
    isShared: true,
  );
}

Trip _trip(int index) {
  return Trip(
    id: 'related-$index',
    externalId: 'related-$index',
    userId: 'user',
    originStationId: 'A',
    originStationName: 'A - Origen',
    destinationStationId: 'B',
    destinationStationName: 'B - Destino',
    startedAt: DateTime(2026, 1, 1).add(Duration(minutes: index * 20)),
    durationSeconds: 600 + index,
    directDistanceMeters: 3000,
    isShared: true,
  );
}
