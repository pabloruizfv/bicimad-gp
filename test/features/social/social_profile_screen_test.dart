import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/achievements/domain/achievement.dart';
import 'package:bicimad_social/features/social/domain/profile_statistics.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/social/presentation/social_profile_screen.dart';
import 'package:bicimad_social/features/stations/data/station_catalog_repository.dart';
import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/stations/domain/station_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';

void main() {
  testWidgets('perfil ajeno reutiliza la tarjeta de General', (tester) async {
    const profile = SocialProfile(
      userId: 'other-user',
      username: 'laura',
      displayName: 'Laura',
      avatarKey: '2.png',
      isPublic: true,
      mostUsedStationName: 'Metro Lago',
    );
    const details = SocialProfileDetails(
      profile: profile,
      statistics: ProfileStatistics(
        totalTrips: 24,
        historySpanDays: 33,
        distinctTripDays: 9,
        totalDurationSeconds: 7500,
        totalDistanceMeters: 18300,
        equivalentAverageSpeedKmh: 8.8,
        tripsWithDistance: 22,
      ),
      followersCount: 37,
      followingCount: 14,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialProfileDetailsProvider.overrideWith(
            (ref, userId) async => details,
          ),
          profileAchievementSummariesProvider.overrideWith(
            (ref, userId) async => [
              AchievementSummary(
                definition: pitStopsAchievement,
                currentLevel: pitStopsAchievement.levels.first,
                progress: 7,
              ),
            ],
          ),
          currentSocialProfileProvider.overrideWith(
            (ref) => const SocialProfile(
              userId: 'current-user',
              username: 'pablo',
              displayName: 'Pablo',
              avatarKey: '1.png',
              isPublic: true,
            ),
          ),
          stationCatalogRepositoryProvider.overrideWithValue(
            _FakeStationCatalogRepository(),
          ),
          stationUsageMapTilesEnabledProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(
          home: SocialProfileScreen(userId: 'other-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('arcade-user-stats-card')),
      findsOneWidget,
    );
    expect(find.text('Laura'), findsOneWidget);
    expect(find.text('@laura'), findsOneWidget);
    expect(find.text('Viajes'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('Días'), findsOneWidget);
    expect(find.text('33'), findsOneWidget);
    expect(find.text('En bici'), findsOneWidget);
    expect(find.text("2h 05'"), findsOneWidget);
    expect(find.text('18.30 km'), findsOneWidget);
    expect(find.text('8.8 km/h'), findsOneWidget);
    expect(find.text('Seguidores'), findsOneWidget);
    expect(find.text('37'), findsOneWidget);
    expect(find.text('Siguiendo'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Visible'), findsOneWidget);
    expect(find.text('Seguir'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('head-to-head-action'))).height,
      tester.getSize(find.widgetWithText(FilledButton, 'Seguir')).height,
    );
    expect(find.text('Estadísticas'), findsNothing);
    expect(find.text('Metro Lago'), findsOneWidget);
    expect(find.byKey(const ValueKey('achievement-showcase')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('achievement-progress-pit_stops')),
      findsOneWidget,
    );
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('achievement-badge-pit_stops')));
    await tester.pumpAndSettle();
    expect(find.text('Requisito'), findsOneWidget);
    expect(find.text('Progreso'), findsNothing);
    expect(find.text('Viajes relacionados'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final displayName = tester.widget<Text>(find.text('Laura'));
    final username = tester.widget<Text>(find.text('@laura'));
    expect(displayName.style?.fontWeight, FontWeight.w900);
    expect(username.style?.fontWeight, isNot(FontWeight.bold));
    expect(username.style?.fontWeight, isNot(FontWeight.w900));

    await tester.tap(find.byKey(const ValueKey('most-used-station-action')));
    await tester.pumpAndSettle();

    expect(find.text('Estación más usada'), findsOneWidget);
    expect(find.byKey(const ValueKey('station_marker_320')), findsOneWidget);
    expect(find.text('320 - Metro Lago'), findsOneWidget);
    expect(find.textContaining('veces'), findsNothing);
  });

  testWidgets('perfil privado no expone estadisticas', (tester) async {
    const profile = SocialProfile(
      userId: 'private-user',
      username: 'perfil_privado',
      displayName: 'Perfil privado',
      avatarKey: '3.png',
      isPublic: false,
      mostUsedStationName: 'Estación privada',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialProfileDetailsProvider.overrideWith(
            (ref, userId) async => const SocialProfileDetails(
              profile: profile,
              followersCount: 4,
              followingCount: 2,
            ),
          ),
          currentSocialProfileProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(
          home: SocialProfileScreen(userId: 'private-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@perfil_privado'), findsOneWidget);
    expect(find.text('Estadísticas privadas'), findsOneWidget);
    expect(find.text('Viajes'), findsNothing);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Oculto'), findsOneWidget);
    expect(find.text('Solicitar'), findsOneWidget);
    expect(find.text('Estación privada'), findsNothing);
    expect(find.byKey(const ValueKey('achievement-showcase')), findsNothing);
  });

  testWidgets('el perfil ajeno confirma antes de dejar de seguir', (
    tester,
  ) async {
    final social = FakeSocialRepository();
    const profile = SocialProfile(
      userId: 'other-user',
      username: 'laura',
      displayName: 'Laura',
      avatarKey: '2.png',
      isPublic: true,
      outgoingFollowStatus: FollowStatus.accepted,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(social),
          socialProfileDetailsProvider.overrideWith(
            (ref, userId) async => const SocialProfileDetails(
              profile: profile,
              followersCount: 1,
              followingCount: 1,
            ),
          ),
          currentSocialProfileProvider.overrideWith(
            (ref) => const SocialProfile(
              userId: 'current-user',
              username: 'pablo',
              displayName: 'Pablo',
              avatarKey: '1.png',
              isPublic: true,
            ),
          ),
        ],
        child: const MaterialApp(
          home: SocialProfileScreen(userId: 'other-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Siguiendo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dejar de seguir?'), findsOneWidget);
    expect(social.operations, isNot(contains('unfollow')));

    await tester.tap(find.widgetWithText(FilledButton, 'Dejar de seguir'));
    await tester.pumpAndSettle();
    expect(social.operations, contains('unfollow'));
  });
}

class _FakeStationCatalogRepository implements StationCatalogRepository {
  final catalog = StationCatalog(
    stations: const [
      Station(
        id: '2297',
        publicCode: '320',
        name: '320 - Metro Lago',
        latitude: 40.4167792,
        longitude: -3.7345247,
      ),
    ],
    updatedAt: DateTime(2026, 8, 20),
  );

  @override
  Future<StationCatalog> getCatalog() async => catalog;

  @override
  void refreshInBackground({bool force = false}) {}

  @override
  Future<void> refreshIfUnknown({
    required String stationId,
    required String stationName,
  }) async {}
}
