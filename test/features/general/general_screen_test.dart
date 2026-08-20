import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/general/domain/station_usage.dart';
import 'package:bicimad_social/features/general/presentation/general_screen.dart';
import 'package:bicimad_social/features/social/domain/profile_statistics.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/trips/domain/trip_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('muestra metricas generales y mapa de estaciones usadas', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          generalTripMetricsProvider.overrideWith((ref) async {
            return GeneralTripMetrics(
              totalTrips: 40,
              distinctTripDays: 12,
              totalDurationSeconds: 36000,
              totalDirectDistanceMeters: 12500,
              tripsWithDistance: 38,
              averageDurationSeconds: 900,
              equivalentAverageSpeedKmh: 1.25,
              firstTripAt: DateTime(2026, 7, 1),
              lastTripAt: DateTime(2026, 8, 2),
              coverageDays: 33,
              periodCount: 2,
            );
          }),
          stationUsageProvider.overrideWith((ref) async {
            return const [
              StationUsage(
                station: Station(
                  id: '1',
                  publicCode: '1',
                  name: 'Origen',
                  latitude: 40.40,
                  longitude: -3.70,
                ),
                uses: 7,
              ),
              StationUsage(
                station: Station(
                  id: '2',
                  publicCode: '2',
                  name: 'Destino',
                  latitude: 40.42,
                  longitude: -3.68,
                ),
                uses: 3,
              ),
            ];
          }),
          selectedAvatarProvider.overrideWith((ref) async {
            return 'assets/avatar/1.png';
          }),
          currentDisplayNameProvider.overrideWith((ref) => 'Pablo'),
          currentSocialProfileProvider.overrideWith(
            (ref) => const SocialProfile(
              userId: 'user-1',
              username: 'pablo',
              displayName: 'Pablo',
              avatarKey: '1.png',
              isPublic: true,
            ),
          ),
          socialProfileDetailsProvider.overrideWith(
            (ref, userId) async => const SocialProfileDetails(
              profile: SocialProfile(
                userId: 'user-1',
                username: 'pablo',
                displayName: 'Pablo',
                avatarKey: '1.png',
                isPublic: true,
              ),
              followersCount: 18,
              followingCount: 11,
            ),
          ),
          stationUsageMapTilesEnabledProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(home: GeneralScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Pablo'), findsOneWidget);
    expect(find.text('@pablo'), findsOneWidget);
    expect(find.text('Seguidores'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('Siguiendo'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('Visible'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('social-connection-footer')),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(find.text('40'), findsWidgets);
    expect(find.text('Días'), findsOneWidget);
    expect(find.text('33'), findsOneWidget);
    expect(find.text('En bici'), findsOneWidget);
    expect(find.text("10h 00'"), findsOneWidget);
    expect(find.text('12.50 km'), findsOneWidget);
    expect(find.text('Velocidad media'), findsOneWidget);
    expect(find.text('1.3 km/h'), findsOneWidget);
    expect(find.text('Actividad'), findsNothing);
    expect(find.text('Ritmo'), findsNothing);
    expect(find.text('Historial'), findsNothing);
    expect(find.text('Distancia'), findsOneWidget);
    expect(find.text('Cobertura de distancia'), findsNothing);
    expect(find.text('Periodos'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Estaciones más usadas'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Estaciones más usadas'), findsOneWidget);
    expect(find.text('Cuenta usos como origen y destino.'), findsNothing);
    expect(find.byIcon(Icons.map_outlined), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('station_marker_1')),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('station_marker_1'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Origen - 7 veces'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('station_marker_1'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Origen - 7 veces'), findsNothing);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final scrollOffset = scrollable.position.pixels;
    final mapGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('station_marker_1'))),
    );
    await mapGesture.moveBy(const Offset(0, -70));
    await mapGesture.up();
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, closeTo(scrollOffset, 0.1));
  });

  testWidgets('la tarjeta navega a Viajes, Comunidad y Ajustes', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/general',
      routes: [
        GoRoute(
          path: '/general',
          builder: (context, state) => const GeneralScreen(),
        ),
        GoRoute(
          path: '/community',
          builder: (context, state) => Scaffold(
            body: Text('community:${state.uri.queryParameters['tab']}'),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const Scaffold(body: Text('profile')),
        ),
        GoRoute(
          path: '/trips',
          builder: (context, state) => const Scaffold(body: Text('trips')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          generalTripMetricsProvider.overrideWith(
            (ref) async => GeneralTripMetrics(
              totalTrips: 1,
              distinctTripDays: 1,
              totalDurationSeconds: 300,
              totalDirectDistanceMeters: 1000,
              tripsWithDistance: 1,
              averageDurationSeconds: 300,
              equivalentAverageSpeedKmh: 12,
              firstTripAt: DateTime(2026, 8, 1),
              lastTripAt: DateTime(2026, 8, 1),
              coverageDays: 1,
              periodCount: 1,
            ),
          ),
          stationUsageProvider.overrideWith((ref) async => const []),
          selectedAvatarProvider.overrideWith(
            (ref) async => 'assets/avatar/1.png',
          ),
          currentDisplayNameProvider.overrideWith((ref) => 'Pablo'),
          currentSocialProfileProvider.overrideWith(
            (ref) => const SocialProfile(
              userId: 'user-1',
              username: 'pablo',
              displayName: 'Pablo',
              avatarKey: '1.png',
              isPublic: true,
            ),
          ),
          socialProfileDetailsProvider.overrideWith(
            (ref, userId) async => const SocialProfileDetails(
              profile: SocialProfile(
                userId: 'user-1',
                username: 'pablo',
                displayName: 'Pablo',
                avatarKey: '1.png',
                isPublic: true,
              ),
              followersCount: 2,
              followingCount: 3,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-trips-action')));
    await tester.pumpAndSettle();
    expect(find.text('trips'), findsOneWidget);

    router.go('/general');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('social-followers-action')));
    await tester.pumpAndSettle();
    expect(find.text('community:followers'), findsOneWidget);

    router.go('/general');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('social-following-action')));
    await tester.pumpAndSettle();
    expect(find.text('community:following'), findsOneWidget);

    router.go('/general');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('social-visibility-action')));
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);
  });

  testWidgets('seleccion cercana y pantalla completa conservan el estado', (
    tester,
  ) async {
    const usages = [
      StationUsage(
        station: Station(
          id: '1',
          publicCode: '1',
          name: 'Origen',
          latitude: 40.40,
          longitude: -3.70,
        ),
        uses: 100,
      ),
      StationUsage(
        station: Station(
          id: '2',
          publicCode: '2',
          name: 'Destino',
          latitude: 40.402,
          longitude: -3.698,
        ),
        uses: 1,
      ),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 330,
              child: StationUsageMap(usages: usages, showTiles: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final smallMarker = find.byKey(const ValueKey('station_marker_2'));
    final initialSize = tester.getSize(smallMarker);
    await tester.tapAt(tester.getCenter(smallMarker) + const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Destino - 1 veces'), findsOneWidget);
    expect(tester.getSize(smallMarker).width, greaterThan(initialSize.width));

    await tester.tapAt(tester.getCenter(smallMarker));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Destino - 1 veces'), findsNothing);

    await tester.tapAt(tester.getCenter(smallMarker));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Destino - 1 veces'), findsOneWidget);

    final mapCanvas = find.byKey(const ValueKey('station_usage_map_canvas'));
    await tester.tapAt(tester.getTopLeft(mapCanvas) + const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Destino - 1 veces'), findsNothing);

    await tester.tapAt(tester.getCenter(smallMarker));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('station_map_fullscreen_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Estaciones más usadas'), findsOneWidget);
    expect(find.text('Destino - 1 veces'), findsOneWidget);

    final largeMarker = find.byKey(const ValueKey('station_marker_1'));
    await tester.tapAt(tester.getCenter(largeMarker));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Origen - 100 veces'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Origen - 100 veces'), findsOneWidget);
  });
}
