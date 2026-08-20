import 'dart:async';

import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/rankings/domain/route_key.dart';
import 'package:bicimad_social/features/rankings/domain/route_summary.dart';
import 'package:bicimad_social/features/rankings/presentation/rankings_screen.dart';
import 'package:bicimad_social/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('permite ordenar rankings por posicion, velocidad o viajes', (
    tester,
  ) async {
    await _pumpRankings(tester);

    expect(_isAbove(tester, 'Ruta posicion', 'Ruta velocidad'), isTrue);
    await tester.tap(find.text('Velocidad'));
    await tester.pumpAndSettle();
    expect(_isAbove(tester, 'Ruta velocidad', 'Ruta posicion'), isTrue);
    await tester.tap(find.text('Viajes'));
    await tester.pumpAndSettle();
    expect(_isAbove(tester, 'Ruta viajes', 'Ruta velocidad'), isTrue);
  });

  testWidgets('un circuito abre el historial en modo rankings', (tester) async {
    final router = GoRouter(
      initialLocation: '/rankings',
      routes: [
        GoRoute(
          path: '/rankings',
          builder: (context, state) => const RankingsScreen(),
        ),
        GoRoute(
          path: '/route-history/:origin/:destination',
          builder: (context, state) =>
              Scaffold(body: Text('view=${state.uri.queryParameters['view']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Card).first);
    await tester.pumpAndSettle();
    expect(find.text('view=rankings'), findsOneWidget);
  });

  testWidgets('alinea avatar, viajes, percentil y velocidad en una fila', (
    tester,
  ) async {
    await _pumpRankings(tester);

    expect(find.text('Mejor marca personal'), findsNothing);
    expect(find.text('1.00 km'), findsNWidgets(3));
    expect(find.byIcon(Icons.route_outlined), findsNothing);
    expect(find.textContaining('01/08/2026'), findsNothing);
    expect(find.text('1 viaje'), findsOneWidget);
    expect(find.text('1 viajes'), findsNothing);
    expect(find.text('2 viajes'), findsOneWidget);
    expect(find.text('P50'), findsOneWidget);
    expect(find.text('5:00'), findsNothing);
    expect(find.text('10.0 km/h'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ranking-personal-best-pill')),
      findsNWidgets(3),
    );
    final personalBestPills = find.byKey(
      const ValueKey('ranking-personal-best-pill'),
    );
    expect(
      find.descendant(
        of: personalBestPills,
        matching: find.byIcon(Icons.leaderboard_outlined),
      ),
      findsNWidgets(3),
    );
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
    expect(
      find.descendant(
        of: personalBestPills,
        matching: find.byIcon(Icons.speed_outlined),
      ),
      findsNWidgets(3),
    );
    expect(find.byType(ProfileAvatar), findsNWidgets(3));
    final avatarCenter = tester.getCenter(find.byType(ProfileAvatar).first);
    final tripsCenter = tester.getCenter(find.text('1 viaje'));
    final bestCenter = tester.getCenter(personalBestPills.first);
    expect(avatarCenter.dx, lessThan(tripsCenter.dx));
    expect(tripsCenter.dx, lessThan(bestCenter.dx));
    expect((avatarCenter.dy - tripsCenter.dy).abs(), lessThan(2));
    expect((tripsCenter.dy - bestCenter.dy).abs(), lessThan(2));
    final tripCountPill = find.byKey(const ValueKey('ranking-trip-count-pill'));
    expect(
      (tester.getSize(tripCountPill.first).height -
              tester.getSize(personalBestPills.first).height)
          .abs(),
      lessThanOrEqualTo(1),
    );
  });

  testWidgets('muestra contenido personal sin esperar los percentiles', (
    tester,
  ) async {
    final historical = Completer<Map<RouteKey, double?>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routePersonalSummariesProvider.overrideWith(
            (ref) async => _summaries,
          ),
          routeHistoricalPercentilesProvider.overrideWith(
            (ref) => historical.future,
          ),
          selectedAvatarProvider.overrideWith(
            (ref) async => 'assets/avatar/1.png',
          ),
        ],
        child: const MaterialApp(home: RankingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Velocidad'));
    await tester.pump();

    expect(find.text('Ruta velocidad'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}

Future<void> _pumpRankings(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides,
      child: const MaterialApp(home: RankingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

bool _isAbove(WidgetTester tester, String first, String second) {
  return tester.getTopLeft(find.text(first)).dy <
      tester.getTopLeft(find.text(second)).dy;
}

final _overrides = [
  routePersonalSummariesProvider.overrideWith((ref) async => _summaries),
  routeHistoricalPercentilesProvider.overrideWith(
    (ref) async => {
      for (final summary in _summaries)
        RouteKey(
          originStationId: summary.originStationId,
          destinationStationId: summary.destinationStationId,
        ): summary.historicalPercentile,
    },
  ),
  selectedAvatarProvider.overrideWith((ref) async => 'assets/avatar/1.png'),
];

final _summaries = [
  _summary(
    id: 'position',
    name: 'Ruta posicion',
    percentile: 50,
    speed: 10,
    tripCount: 1,
  ),
  _summary(
    id: 'speed',
    name: 'Ruta velocidad',
    percentile: 84,
    speed: 20,
    tripCount: 2,
  ),
  _summary(
    id: 'trips',
    name: 'Ruta viajes',
    percentile: 90,
    speed: 8,
    tripCount: 7,
  ),
];

RouteSummary _summary({
  required String id,
  required String name,
  required double percentile,
  required double speed,
  required int tripCount,
}) {
  return RouteSummary(
    originStationId: id,
    originStationName: name,
    destinationStationId: 'destination-$id',
    destinationStationName: 'Destino $id',
    personalBestDurationSeconds: 300,
    personalBestDistanceMeters: 1000,
    personalBestSpeedKmh: speed,
    personalTripCount: tripCount,
    personalBestStartedAt: DateTime(2026, 8, 1, 10),
    historicalPercentile: percentile,
    currentUserPosition: null,
    totalUsers: 1,
  );
}
