import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/achievements/domain/achievement.dart';
import 'package:bicimad_social/features/achievements/domain/achievement_service.dart';
import 'package:bicimad_social/features/trips/domain/journey_builder.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';

void main() {
  const service = AchievementService();

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (1, AchievementLevelId.graphite),
    (9, AchievementLevelId.graphite),
    (10, AchievementLevelId.bronze),
    (49, AchievementLevelId.bronze),
    (50, AchievementLevelId.silver),
    (99, AchievementLevelId.silver),
    (100, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} pit stops resuelve ${testCase.$2}', () {
      final journeys = testCase.$1 == 0
          ? const <Trip>[]
          : [_journey('journey', pitStops: testCase.$1, day: 2)];
      final progress = _progressFor(
        service.evaluate(journeys: journeys),
        pitStopsAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
      expect(
        progress.visibleAssetPath,
        testCase.$2 == null
            ? pitStopsAchievement.lockedAssetPath
            : pitStopsAchievement.levels
                  .firstWhere((level) => level.id == testCase.$2)
                  .assetPath,
      );
    });
  }

  test('usa los pit stops construidos por JourneyBuilder', () {
    final stages = [
      _stage('ab', 'A', 'B', DateTime(2026, 1, 1, 10)),
      _stage('bc', 'B', 'C', DateTime(2026, 1, 1, 10, 11)),
    ];
    final journeys = const JourneyBuilder().buildJourneys(stages);

    final progress = _progressFor(
      service.evaluate(journeys: journeys),
      pitStopsAchievement.id,
    );

    expect(journeys.single.pitStops, hasLength(1));
    expect(progress.progress, 1);
    expect(progress.currentLevel?.id, AchievementLevelId.graphite);
  });

  test('calcula desbloqueos retroactivos con la fecha del journey', () {
    final first = _journey('first', pitStops: 1, day: 2);
    final second = _journey('second', pitStops: 9, day: 7);

    final progress = _progressFor(
      service.evaluate(journeys: [second, first]),
      pitStopsAchievement.id,
    );

    expect(progress.unlocks[AchievementLevelId.graphite], first.endedAt);
    expect(progress.unlocks[AchievementLevelId.bronze], second.endedAt);
  });

  test(
    'reconstruccion persistida no duplica niveles y conserva la fecha menor',
    () {
      final later = DateTime.utc(2026, 3, 1);
      final earlier = DateTime.utc(2026, 2, 1);
      final persisted = [
        UserAchievement(
          categoryId: 'pit_stops',
          levelId: AchievementLevelId.graphite,
          threshold: 1,
          unlockedAt: later,
        ),
        UserAchievement(
          categoryId: 'pit_stops',
          levelId: AchievementLevelId.graphite,
          threshold: 1,
          unlockedAt: earlier,
        ),
      ];

      final progress = _progressFor(
        service.evaluate(journeys: const [], persisted: persisted),
        pitStopsAchievement.id,
      );

      expect(progress.unlocks, hasLength(1));
      expect(progress.unlocks[AchievementLevelId.graphite], earlier);
      expect(progress.progress, 1);
    },
  );

  test('restaura el nivel persistido desde el repositorio social', () async {
    final repository = FakeSocialRepository(
      achievements: [
        UserAchievement(
          categoryId: 'pit_stops',
          levelId: AchievementLevelId.bronze,
          threshold: 10,
          unlockedAt: DateTime.utc(2026, 1, 10),
          progress: 37,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        socialRepositoryProvider.overrideWithValue(repository),
        myTripsProvider.overrideWith((ref) async => const []),
        myTripStagesProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);

    final progress = await container.read(
      ownAchievementProgressProvider.future,
    );

    final pitStops = _progressFor(progress, pitStopsAchievement.id);
    expect(pitStops.currentLevel?.id, AchievementLevelId.bronze);
    expect(pitStops.progress, 37);
    expect(repository.operations, contains('getUserAchievements'));
  });

  test('el resumen social conserva el progreso agregado exacto', () {
    final summaries = service.summaries([
      UserAchievement(
        categoryId: pitStopsAchievement.id,
        levelId: AchievementLevelId.bronze,
        threshold: 10,
        progress: 37,
        unlockedAt: DateTime.utc(2026, 1, 10),
      ),
    ]);

    final pitStops = summaries.firstWhere(
      (summary) => summary.definition.id == pitStopsAchievement.id,
    );
    expect(pitStops.currentLevel?.id, AchievementLevelId.bronze);
    expect(pitStops.progress, 37);
  });

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (1, AchievementLevelId.graphite),
    (9, AchievementLevelId.graphite),
    (10, AchievementLevelId.bronze),
    (49, AchievementLevelId.bronze),
    (50, AchievementLevelId.silver),
    (99, AchievementLevelId.silver),
    (100, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} viajes rapidos resuelve ${testCase.$2}', () {
      final journeys = [
        for (var index = 0; index < testCase.$1; index++)
          _journey(
            'fast-$index',
            pitStops: 0,
            day: 1,
            minute: index,
            speedKmh: 14.1,
          ),
      ];
      final progress = _progressFor(
        service.evaluate(journeys: journeys),
        fastTripsAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
      expect(progress.relatedJourneys, hasLength(testCase.$1));
    });
  }

  test('solo cuenta velocidades estrictamente superiores a 14 km/h', () {
    final journeys = [
      _journey('below', pitStops: 0, day: 1, speedKmh: 13.9),
      _journey('equal', pitStops: 0, day: 2, speedKmh: 14),
      _journey('above', pitStops: 0, day: 3, speedKmh: 14.1),
      _journey('unknown', pitStops: 0, day: 4),
    ];

    final progress = _progressFor(
      service.evaluate(journeys: journeys),
      fastTripsAchievement.id,
    );

    expect(progress.progress, 1);
    expect(progress.relatedJourneys.single.id, 'above');
    expect(progress.unlocks[AchievementLevelId.graphite], journeys[2].endedAt);
  });

  test('un journey rapido con pit stops cuenta una sola vez', () {
    final journey = _journey(
      'fast-with-stops',
      pitStops: 3,
      day: 2,
      speedKmh: 18,
    );

    final progresses = service.evaluate(journeys: [journey]);

    expect(_progressFor(progresses, fastTripsAchievement.id).progress, 1);
    expect(_progressFor(progresses, pitStopsAchievement.id).progress, 3);
  });

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (1, AchievementLevelId.graphite),
    (9, AchievementLevelId.graphite),
    (10, AchievementLevelId.bronze),
    (49, AchievementLevelId.bronze),
    (50, AchievementLevelId.silver),
    (99, AchievementLevelId.silver),
    (100, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} viajes largos resuelve ${testCase.$2}', () {
      final journeys = [
        for (var index = 0; index < testCase.$1; index++)
          _journey(
            'long-$index',
            pitStops: 0,
            day: 1,
            minute: index,
            distanceMeters: 5001,
          ),
      ];
      final progress = _progressFor(
        service.evaluate(journeys: journeys),
        longTripsAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
      expect(progress.relatedJourneys, hasLength(testCase.$1));
    });
  }

  test('solo cuenta distancias estrictamente superiores a 5 km', () {
    final journeys = [
      _journey('below-5k', pitStops: 0, day: 1, distanceMeters: 4999.9),
      _journey('equal-5k', pitStops: 0, day: 2, distanceMeters: 5000),
      _journey('above-5k', pitStops: 0, day: 3, distanceMeters: 5000.1),
      _journey('unknown-distance', pitStops: 0, day: 4),
    ];

    final progress = _progressFor(
      service.evaluate(journeys: journeys),
      longTripsAchievement.id,
    );

    expect(progress.progress, 1);
    expect(progress.relatedJourneys.single.id, 'above-5k');
    expect(progress.unlocks[AchievementLevelId.graphite], journeys[2].endedAt);
    expect(longTripsAchievement.formatProgress(1), '1 viaje largo');
    expect(longTripsAchievement.formatProgress(2), '2 viajes largos');
  });

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (1, AchievementLevelId.graphite),
    (9, AchievementLevelId.graphite),
    (10, AchievementLevelId.bronze),
    (49, AchievementLevelId.bronze),
    (50, AchievementLevelId.silver),
    (99, AchievementLevelId.silver),
    (100, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} viajes nocturnos resuelve ${testCase.$2}', () {
      final journeys = [
        for (var index = 0; index < testCase.$1; index++)
          _journey(
            'night-$index',
            pitStops: 0,
            day: 1,
          ).copyWith(startedAt: DateTime(2026, 1, 1, index % 6)),
      ];
      final daytime = _journey(
        'daytime',
        pitStops: 0,
        day: 2,
      ).copyWith(startedAt: DateTime(2026, 1, 2, 6));
      final progress = _progressFor(
        service.evaluate(journeys: [...journeys, daytime]),
        nightTripsAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
      expect(progress.relatedJourneys, hasLength(testCase.$1));
    });
  }

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (9, null),
    (10, AchievementLevelId.graphite),
    (49, AchievementLevelId.graphite),
    (50, AchievementLevelId.bronze),
    (199, AchievementLevelId.bronze),
    (200, AchievementLevelId.silver),
    (499, AchievementLevelId.silver),
    (500, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} rutas exploradas resuelve ${testCase.$2}', () {
      final routes = [
        for (var index = 0; index < testCase.$1; index++)
          _journey('route-$index', pitStops: 0, day: 1).copyWith(
            originStationId: 'O$index',
            originStationName: 'O$index - Origen',
            destinationStationId: 'D$index',
            destinationStationName: 'D$index - Destino',
          ),
      ];
      final progress = _progressFor(
        service.evaluate(journeys: routes),
        exploredRoutesAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
    });
  }

  test(
    'rutas exploradas conserva el sentido y puede usar los viajes de ranking',
    () {
      final journeys = [
        _journey('ab', pitStops: 0, day: 1),
        _journey('ab-duplicate', pitStops: 0, day: 2),
      ];
      final reverse = journeys.first.copyWith(
        id: 'ba',
        originStationId: 'B',
        originStationName: 'B - Destino',
        destinationStationId: 'A',
        destinationStationName: 'A - Origen',
      );

      final progress = _progressFor(
        service.evaluate(
          journeys: journeys,
          routeJourneys: [...journeys, reverse],
        ),
        exploredRoutesAchievement.id,
      );

      expect(progress.progress, 2);
    },
  );

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (9, null),
    (10, AchievementLevelId.graphite),
    (49, AchievementLevelId.graphite),
    (50, AchievementLevelId.bronze),
    (199, AchievementLevelId.bronze),
    (200, AchievementLevelId.silver),
    (499, AchievementLevelId.silver),
    (500, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} usos de una estacion resuelve ${testCase.$2}', () {
      final journeys = [
        for (var index = 0; index < testCase.$1; index++)
          _stationJourney(index),
      ];

      final progress = _progressFor(
        service.evaluate(journeys: journeys),
        favoriteStationAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
      expect(progress.relatedJourneys, hasLength(testCase.$1));
    });
  }

  test('agrupa la estacion por codigo publico extraido del nombre', () {
    final journeys = [
      for (var index = 0; index < 10; index++)
        _stationJourney(index).copyWith(
          originStationId: 'gbfs-${1000 + index}',
          originStationName: index.isEven
              ? '0172 - Estación de tren de Delicias'
              : '172 - Estación de tren de Delicias',
        ),
    ];

    final progress = _progressFor(
      service.evaluate(journeys: journeys),
      favoriteStationAchievement.id,
    );

    expect(progress.progress, 10);
    expect(progress.currentLevel?.id, AchievementLevelId.graphite);
    expect(
      progress.unlocks[AchievementLevelId.graphite],
      journeys.last.endedAt,
    );
  });

  test('los pit stops intermedios no cuentan como extremos del journey', () {
    final journeys = [
      for (var index = 0; index < 10; index++)
        _stationJourney(index).copyWith(
          originStationId: '${100 + index}',
          originStationName: '${100 + index} - Origen',
          pitStops: const [
            PitStop(
              stationId: '200',
              stationName: '200 - Intermedia',
              durationSeconds: 30,
            ),
          ],
        ),
    ];

    final progress = _progressFor(
      service.evaluate(journeys: journeys),
      favoriteStationAchievement.id,
    );

    expect(progress.progress, 1);
    expect(progress.currentLevel, isNull);
  });

  for (final testCase in <(int, AchievementLevelId?)>[
    (0, null),
    (1, null),
    (2, AchievementLevelId.graphite),
    (3, AchievementLevelId.bronze),
    (4, AchievementLevelId.silver),
    (5, AchievementLevelId.gold),
  ]) {
    test('${testCase.$1} usos de una bici resuelve ${testCase.$2}', () {
      final journeys = [
        for (var index = 0; index < testCase.$1; index++)
          _journey(
            'bike-$index',
            pitStops: 0,
            day: 1,
            minute: index,
          ).copyWith(bikeId: '00001234'),
      ];

      final progress = _progressFor(
        service.evaluate(journeys: journeys),
        favoriteBikeAchievement.id,
      );

      expect(progress.progress, testCase.$1);
      expect(progress.currentLevel?.id, testCase.$2);
      expect(progress.relatedJourneys, hasLength(testCase.$1));
    });
  }

  test(
    'una misma bici repetida en varias etapas cuenta una vez por journey',
    () {
      final firstJourney = _journey('multi-stage', pitStops: 1, day: 1)
          .copyWith(
            stageDetails: const [
              JourneyStageDetails(
                stageId: 'stage-a',
                sourceTripId: 'source-a',
                bikeId: '00077',
                tripCost: null,
              ),
              JourneyStageDetails(
                stageId: 'stage-b',
                sourceTripId: 'source-b',
                bikeId: '00077',
                tripCost: null,
              ),
            ],
          );
      final secondJourney = _journey(
        'single-stage',
        pitStops: 0,
        day: 2,
      ).copyWith(bikeId: '77');

      final firstProgress = _progressFor(
        service.evaluate(journeys: [firstJourney]),
        favoriteBikeAchievement.id,
      );
      final combinedProgress = _progressFor(
        service.evaluate(journeys: [firstJourney, secondJourney]),
        favoriteBikeAchievement.id,
      );

      expect(firstProgress.progress, 1);
      expect(combinedProgress.progress, 2);
      expect(combinedProgress.currentLevel?.id, AchievementLevelId.graphite);
      expect(combinedProgress.relatedJourneys, hasLength(2));
    },
  );

  test('expone todas las bicis empatadas como favoritas', () {
    final journeys = [
      _journey('bike-9-a', pitStops: 0, day: 1).copyWith(bikeId: '0009'),
      _journey('bike-10-a', pitStops: 0, day: 2).copyWith(bikeId: '0010'),
      _journey('bike-9-b', pitStops: 0, day: 3).copyWith(bikeId: '9'),
      _journey('bike-10-b', pitStops: 0, day: 4).copyWith(bikeId: '10'),
      _journey('bike-20', pitStops: 0, day: 5).copyWith(bikeId: '20'),
    ];

    final progress = _progressFor(
      service.evaluate(journeys: journeys),
      favoriteBikeAchievement.id,
    );

    expect(progress.progress, 2);
    expect(progress.relatedBikeIds, ['9', '10']);
    expect(progress.relatedJourneys.map((journey) => journey.id), [
      'bike-9-a',
      'bike-10-a',
      'bike-9-b',
      'bike-10-b',
    ]);
  });
}

AchievementProgress _progressFor(
  List<AchievementProgress> progresses,
  String categoryId,
) {
  return progresses.firstWhere(
    (progress) => progress.definition.id == categoryId,
  );
}

Trip _journey(
  String id, {
  required int pitStops,
  required int day,
  int minute = 0,
  double? speedKmh,
  double? distanceMeters,
}) {
  const durationSeconds = 600;
  return Trip(
    id: id,
    externalId: id,
    userId: 'user',
    originStationId: 'A',
    originStationName: 'A - Origen',
    destinationStationId: 'B',
    destinationStationName: 'B - Destino',
    startedAt: DateTime(2026, 1, day, 10).add(Duration(minutes: minute)),
    durationSeconds: durationSeconds,
    directDistanceMeters:
        distanceMeters ??
        (speedKmh == null ? null : speedKmh * durationSeconds / 3.6),
    isShared: true,
    pitStops: [
      for (var index = 0; index < pitStops; index++)
        PitStop(
          stationId: 'P$index',
          stationName: 'Parada $index',
          durationSeconds: 60,
        ),
    ],
  );
}

Trip _stage(String id, String origin, String destination, DateTime startedAt) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user',
    originStationId: origin,
    originStationName: origin,
    destinationStationId: destination,
    destinationStationName: destination,
    startedAt: startedAt,
    durationSeconds: 600,
    isShared: true,
  );
}

Trip _stationJourney(int index) {
  return Trip(
    id: 'station-$index',
    externalId: 'station-$index',
    userId: 'user',
    originStationId: '172',
    originStationName: '172 - Estación de tren de Delicias',
    destinationStationId: '${300 + index}',
    destinationStationName: '${300 + index} - Destino $index',
    startedAt: DateTime(2026, 1, 1, 10).add(Duration(minutes: index * 20)),
    durationSeconds: 600,
    isShared: true,
  );
}
