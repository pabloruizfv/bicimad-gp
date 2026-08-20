import 'dart:io';

import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/rankings/domain/route_key.dart';
import 'package:bicimad_social/features/trips/data/legacy_route_model_repository.dart';
import 'package:bicimad_social/features/trips/domain/legacy_route_model.dart';
import 'package:bicimad_social/features/trips/domain/station_code.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/presentation/route_history_screen.dart';
import 'package:bicimad_social/features/trips/presentation/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('extrae codigo publico de estacion en Dart', () {
    expect(extractPublicStationCode('34 - Jacinto Benavente'), '34');
    expect(extractPublicStationCode('001 B - Puerta del Sol B'), '1b');
    expect(
      canonicalStationCode(stationId: '164', stationName: 'Otro nombre'),
      '164',
    );
    expect(
      canonicalStationCode(
        stationId: 'api-id',
        stationName: '164 - Paseo de las Delicias',
      ),
      '164',
    );
    expect(
      canonicalStationCode(
        stationId: '999',
        stationName: '164 - Paseo de las Delicias',
      ),
      '164',
    );
    expect(extractPublicStationCode('Sin codigo'), isNull);
  });

  test('normaliza y suaviza densidades de histograma', () {
    final model = _model(displayedCount: 10);
    final points = model.smoothedDensityPoints();

    expect(model.canPlot, isTrue);
    expect(points.first.seconds, model.bestSeconds);
    expect(points.first.density, 0);
    expect(points.last.seconds, model.upperCutoffSeconds);
    expect(points.last.density, 0);
    expect(points.where((point) => point.density > 0), isNotEmpty);
  });

  test('calcula percentil mediante acumulada del histograma', () {
    final model = _model(displayedCount: 10);

    expect(model.percentileForDuration(60), 0);
    expect(model.percentileForDuration(100), closeTo(20, 0.001));
    expect(model.percentileForDuration(140), closeTo(50, 0.001));
    expect(model.percentileForDuration(260), isNull);
    expect(model.isAboveDisplayedRange(260), isTrue);
  });

  test('reconstruye el tiempo tipico desde el mismo histograma', () {
    final model = _model(displayedCount: 10);

    expect(model.durationForPercentile(50), closeTo(140, 0.001));
  });

  test('consulta el modelo desde SQLite', () async {
    final databasePath = await _createTempDatabase(totalCount: 30);
    final repository = SqliteLegacyRouteModelRepository(
      databasePath: databasePath,
    );

    final model = await repository.getRouteModel(
      originStationCode: '34',
      destinationStationCode: '164',
    );
    final missing = await repository.getRouteModel(
      originStationCode: '164',
      destinationStationCode: '34',
    );
    repository.close();

    expect(model, isNotNull);
    expect(model?.totalCount, 30);
    expect(model?.displayedCount, 28);
    expect(model?.outlierCount, 2);
    expect(model?.upperCutoffSeconds, 220);
    expect(missing, isNull);
  });

  testWidgets('muestra estado sin historico comparable', (tester) async {
    await _pumpRouteHistory(tester, model: null, trips: [_trip('selected')]);
    await _scrollToLegacySection(tester);

    expect(
      find.text('No hay suficiente historico comparable para esta ruta.'),
      findsOneWidget,
    );
  });

  testWidgets('usa anclaje en origen y meta ajedrezada en destino', (
    tester,
  ) async {
    await _pumpRouteHistory(
      tester,
      model: null,
      trips: [_trip('selected')],
      showOverview: true,
    );

    expect(
      find.byKey(const ValueKey('route-origin-dock-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-destination-checkered-marker')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('detalle normal muestra datos y un unico resumen personal', (
    tester,
  ) async {
    final selected = _trip('selected', distanceMeters: 1000, tripCost: '1.2');
    final slower = _trip('slower', durationSeconds: 150);
    final inverse = Trip(
      id: 'inverse',
      externalId: 'inverse',
      userId: 'user-1',
      originStationId: '164',
      originStationName: '164 - Paseo de las Delicias',
      destinationStationId: '34',
      destinationStationName: '34 - Jacinto Benavente',
      startedAt: DateTime(2026, 8, 3, 11),
      durationSeconds: 180,
      isShared: true,
    );

    await _pumpRouteHistory(
      tester,
      model: null,
      trips: [selected, slower],
      allTrips: [selected, slower, inverse],
      showOverview: true,
    );

    expect(find.text('Datos del viaje'), findsNothing);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Fin'), findsOneWidget);
    expect(find.text('Duración'), findsOneWidget);
    expect(find.text('Velocidad'), findsOneWidget);
    expect(find.text('Domingo 02/08/2026 10:00'), findsOneWidget);
    expect(find.text('Domingo 02/08/2026 10:02'), findsOneWidget);
    expect(find.text('2 min 00 s'), findsOneWidget);
    expect(find.text('30.0 km/h'), findsOneWidget);
    expect(find.text('1.00 km · 2:00 · 30.0 km/h · 1,2 €'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-personal-context-card')),
      260,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu historial en esta ruta'), findsOneWidget);
    expect(find.text('Viajes'), findsOneWidget);
    expect(find.text('Sentido inverso'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('de 2'), findsOneWidget);
    expect(find.text('Ver en Rankings'), findsOneWidget);
    expect(find.text('Mis viajes vs Histórico usuarios BiciMAD'), findsNothing);
    expect(find.text('Todos mis viajes'), findsNothing);
  });

  testWidgets('muestra duracion y velocidad exactas en todos los tramos', (
    tester,
  ) async {
    final stages = [
      _stage(
        id: 'stage-1',
        originId: '34',
        destinationId: '50',
        startedAt: DateTime(2026, 8, 2, 10),
        durationSeconds: 120,
        distanceMeters: 1000,
        tripCost: '0.5',
      ),
      _stage(
        id: 'stage-2',
        originId: '50',
        destinationId: '60',
        startedAt: DateTime(2026, 8, 2, 10, 2, 30),
        durationSeconds: 180,
        distanceMeters: 1500,
        tripCost: '0.7',
      ),
      _stage(
        id: 'stage-3',
        originId: '60',
        destinationId: '164',
        startedAt: DateTime(2026, 8, 2, 10, 6, 15),
        durationSeconds: 240,
        distanceMeters: 2000,
        tripCost: '0.9',
      ),
    ];
    final journey = Trip(
      id: 'selected',
      externalId: 'stage-1+stage-2+stage-3',
      userId: 'user-1',
      originStationId: '34',
      originStationName: '34 - Jacinto Benavente',
      destinationStationId: '164',
      destinationStationName: '164 - Paseo de las Delicias',
      startedAt: DateTime(2026, 8, 2, 10),
      durationSeconds: 615,
      isShared: true,
      pitStops: const [
        PitStop(
          stationId: '50',
          stationName: '50 - Parada intermedia uno',
          durationSeconds: 30,
        ),
        PitStop(
          stationId: '60',
          stationName: '60 - Parada intermedia dos',
          durationSeconds: 45,
        ),
      ],
      stageIds: const ['stage-1', 'stage-2', 'stage-3'],
    );

    await _pumpRouteHistory(
      tester,
      model: null,
      trips: [journey],
      stages: stages,
      showOverview: true,
    );

    expect(find.text('1.00 km · 2:00 · 30.0 km/h · 0,5 €'), findsOneWidget);
    expect(find.text('1.50 km · 3:00 · 30.0 km/h · 0,7 €'), findsOneWidget);
    expect(find.text('2.00 km · 4:00 · 30.0 km/h · 0,9 €'), findsOneWidget);
  });

  testWidgets('no visualiza curva con sample_count menor de 5', (tester) async {
    await _pumpRouteHistory(
      tester,
      model: _model(displayedCount: 4),
      trips: [_trip('selected')],
    );
    await _scrollToLegacySection(tester);
    expect(find.text('Muestra'), findsNothing);
    expect(
      find.text('No hay suficiente historico comparable para esta ruta.'),
      findsOneWidget,
    );
  });

  testWidgets('visualiza curva con sample_count >= 5', (tester) async {
    await _pumpRouteHistory(
      tester,
      model: _model(displayedCount: 5),
      trips: [_trip('selected')],
    );
    await _scrollToLegacySection(tester);
    expect(
      find.text('Mis viajes vs Histórico usuarios BiciMAD'),
      findsOneWidget,
    );
    expect(find.text('Eje X: duracion. Eje Y: densidad.'), findsNothing);
    expect(find.text('Valores mostrados'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
      find.byKey(const ValueKey('legacy-chart-avatar-selected')),
      findsOneWidget,
    );
    expect(find.text('USUARIOS 2017-22'), findsOneWidget);
    expect(find.text('MIS VIAJES'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('historical-distribution-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('personal-comparison-avatar')),
      findsOneWidget,
    );
    expect(find.text('Viajes'), findsNWidgets(2));
    expect(find.text('Mejor'), findsNWidgets(2));
    expect(find.text('Típico'), findsNWidgets(2));
    expect(find.text('Muestra'), findsNothing);
    expect(find.text('Periodo'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Todos mis viajes'),
      260,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    final historicalCard = find
        .ancestor(
          of: find.text('Mis viajes vs Histórico usuarios BiciMAD'),
          matching: find.byType(Card),
        )
        .evaluate()
        .single;
    final personalTripsCard = find
        .ancestor(
          of: find.text('Todos mis viajes'),
          matching: find.byType(Card),
        )
        .evaluate()
        .single;
    expect(personalTripsCard, isNot(same(historicalCard)));
  });

  testWidgets('muestra bicicleta y precio en el detalle del viaje', (
    tester,
  ) async {
    await _pumpRouteHistory(
      tester,
      model: _model(displayedCount: 5),
      trips: [_trip('selected', bikeId: 'bike-fake-1', tripCost: '1.2300')],
      showOverview: true,
    );

    expect(find.text('Bicicleta'), findsOneWidget);
    expect(find.text('bike-fake-1'), findsOneWidget);
    expect(find.text('Precio'), findsOneWidget);
    expect(find.text('1,2300 €'), findsOneWidget);
  });

  testWidgets('no muestra seleccion roja para viajes fuera de rango', (
    tester,
  ) async {
    await _pumpRouteHistory(
      tester,
      model: _model(displayedCount: 5, outlierCount: 2),
      trips: [_trip('selected', durationSeconds: 260)],
    );
    await _scrollToLegacySection(tester);

    expect(find.text('Valores atipicos excluidos'), findsNothing);
    expect(find.text('por encima del rango habitual'), findsNothing);
    expect(find.text('Percentil del viaje seleccionado'), findsNothing);
  });

  testWidgets('lista personal reutiliza tarjetas sin extremos y con pit stop', (
    tester,
  ) async {
    const pitStop = PitStop(
      stationId: '50',
      stationName: '50 - Estacion intermedia',
      durationSeconds: 75,
    );
    await _pumpRouteHistory(
      tester,
      model: _model(displayedCount: 5),
      trips: [
        _trip('selected', pitStops: const [pitStop]),
        _trip('second', durationSeconds: 130),
        _trip('third', durationSeconds: 140),
        _trip('fourth', durationSeconds: 150),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('Todos mis viajes'),
      260,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    final tripCard = find.byType(TripCard);
    expect(tripCard, findsNWidgets(4));
    expect(find.text('Viajes'), findsNWidgets(2));
    expect(find.text('Tiempo típico'), findsNothing);
    expect(
      find.descendant(
        of: tripCard,
        matching: find.text('34 - Jacinto Benavente'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: tripCard,
        matching: find.text('164 - Paseo de las Delicias'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: tripCard,
        matching: find.textContaining('1:15  ·  50 - Estacion intermedia'),
      ),
      findsOneWidget,
    );
    expect(find.text('Record personal'), findsNothing);
    expect(find.byKey(const ValueKey('trip-rank-medal-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-rank-medal-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-rank-medal-3')), findsOneWidget);
    expect(
      find.descendant(
        of: tripCard,
        matching: find.byIcon(Icons.route_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: tripCard,
        matching: find.byIcon(Icons.leaderboard_outlined),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: tripCard,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.data?.startsWith('P') == true,
        ),
      ),
      findsNWidgets(4),
    );

    final selectedSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('trip-card-selection-selected')),
    );
    final decoration = selectedSurface.decoration as BoxDecoration;
    expect(decoration.border, isNull);
    expect(
      tester
          .widgetList<InkWell>(
            find.descendant(of: tripCard, matching: find.byType(InkWell)),
          )
          .every((inkWell) => inkWell.onTap == null),
      isTrue,
    );
  });

  test('colores de ranking distinguen podium y resto', () {
    expect(tripRankAccentColor(1), tripRankGoldAccent);
    expect(tripRankAccentColor(2), tripRankSilverAccent);
    expect(tripRankAccentColor(3), tripRankBronzeAccent);
    expect(tripRankAccentColor(4), Colors.black);
    expect(tripRankBackgroundColor(1), isNot(Colors.transparent));
    expect(tripRankBackgroundColor(2), isNot(Colors.transparent));
    expect(tripRankBackgroundColor(3), isNot(Colors.transparent));
    expect(tripRankBackgroundColor(4), Colors.transparent);
  });

  testWidgets('modo rankings muestra resumen OD sin datos ni pit stops', (
    tester,
  ) async {
    const pitStop = PitStop(
      stationId: '50',
      stationName: '50 - Estacion intermedia',
      durationSeconds: 75,
    );
    await _pumpRouteHistory(
      tester,
      model: _model(displayedCount: 5),
      trips: [
        _trip(
          'selected',
          distanceMeters: 1234,
          pitStops: const [pitStop],
          bikeId: 'bike-fake',
          tripCost: '1.2',
        ),
      ],
    );

    final overview = find.byKey(const ValueKey('generic-route-overview-card'));
    expect(overview, findsOneWidget);
    expect(
      find.descendant(
        of: overview,
        matching: find.text('34 - Jacinto Benavente'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overview,
        matching: find.text('164 - Paseo de las Delicias'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.text('1.23 km')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overview,
        matching: find.text('50 - Estacion intermedia'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: overview, matching: find.text('Inicio')),
      findsNothing,
    );
    expect(
      find.descendant(of: overview, matching: find.text('Precio')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: overview,
        matching: find.byKey(const ValueKey('generic-route-map')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('los indicadores abren Rankings directo e inverso', (
    tester,
  ) async {
    final direct = _trip('selected');
    final inverse = Trip(
      id: 'inverse',
      externalId: 'inverse',
      userId: 'user-1',
      originStationId: '164',
      originStationName: '164 - Paseo de las Delicias',
      destinationStationId: '34',
      destinationStationName: '34 - Jacinto Benavente',
      startedAt: DateTime(2026, 8, 3, 10),
      durationSeconds: 140,
      isShared: true,
    );
    final router = GoRouter(
      initialLocation: '/route-history/34/164',
      routes: [
        GoRoute(
          path: '/route-history/:origin/:destination',
          builder: (context, state) {
            final origin = state.pathParameters['origin']!;
            final destination = state.pathParameters['destination']!;
            if (state.uri.queryParameters['view'] == 'rankings') {
              return Scaffold(body: Text('ranking:$origin->$destination'));
            }
            return RouteHistoryScreen(
              routeKey: RouteKey(
                originStationId: origin,
                destinationStationId: destination,
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routeTripsProvider.overrideWith((ref, routeKey) async => [direct]),
          myTripsProvider.overrideWith((ref) async => [direct, inverse]),
          myTripStagesProvider.overrideWith((ref) async => [direct, inverse]),
          selectedAvatarProvider.overrideWith(
            (ref) async => 'assets/avatar/1.png',
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final forwardAction = find.descendant(
      of: find.byKey(const ValueKey('personal-route-forward-action')),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(forwardAction).onTap!.call();
    await tester.pumpAndSettle();
    expect(find.text('ranking:34->164'), findsOneWidget);

    router.go('/route-history/34/164');
    await tester.pumpAndSettle();
    final inverseAction = find.descendant(
      of: find.byKey(const ValueKey('personal-route-inverse-action')),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(inverseAction).onTap!.call();
    await tester.pumpAndSettle();
    expect(find.text('ranking:164->34'), findsOneWidget);
  });

  testWidgets('modo rankings omite resumen y abre el viaje pulsado', (
    tester,
  ) async {
    final parentJourney = Trip(
      id: 'journey-parent',
      externalId: 'parent',
      userId: 'user-1',
      originStationId: '1',
      originStationName: '1 - Origen completo',
      destinationStationId: '2',
      destinationStationName: '2 - Destino completo',
      startedAt: DateTime(2026, 8, 2, 10),
      durationSeconds: 240,
      isShared: true,
    );
    final projectedTrip = _trip('projected', durationSeconds: 100).copyWith(
      parentJourneyId: parentJourney.id,
      parentJourneyOriginStationId: parentJourney.originStationId,
      parentJourneyDestinationStationId: parentJourney.destinationStationId,
    );
    final router = GoRouter(
      initialLocation: '/route-history/34/164?view=rankings',
      routes: [
        GoRoute(
          path: '/route-history/:origin/:destination',
          builder: (context, state) {
            final rankingsView =
                state.uri.queryParameters['view'] == 'rankings';
            return RouteHistoryScreen(
              routeKey: RouteKey(
                originStationId: state.pathParameters['origin']!,
                destinationStationId: state.pathParameters['destination']!,
              ),
              selectedTripId: state.uri.queryParameters['selectedTripId'],
              showOverview: !rankingsView,
              allowTripNavigation: rankingsView,
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routeTripsProvider.overrideWith(
            (ref, routeKey) async => routeKey.originStationId == '34'
                ? [projectedTrip]
                : [parentJourney],
          ),
          legacyRouteModelProvider.overrideWith(
            (ref, routeKey) async => _model(displayedCount: 5),
          ),
          myRankingTripsProvider.overrideWith(
            (ref) async => [projectedTrip, parentJourney],
          ),
          myTripStagesProvider.overrideWith((ref) async => [parentJourney]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ranking 34 → 164'), findsOneWidget);
    expect(find.text('Viaje 34 → 164'), findsNothing);
    expect(
      find.byKey(const ValueKey('generic-route-overview-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('route-origin-dock-icon')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Todos mis viajes'),
      260,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TripCard).first);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/route-history/1/2');
    expect(
      router.state.uri.queryParameters['selectedTripId'],
      'journey-parent',
    );
    expect(find.text('1 - Origen completo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('route-origin-dock-icon')),
      findsOneWidget,
    );
  });
}

Future<void> _scrollToLegacySection(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Mis viajes vs Histórico usuarios BiciMAD'),
    260,
    scrollable: find.byType(Scrollable),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpRouteHistory(
  WidgetTester tester, {
  required LegacyRouteModel? model,
  required List<Trip> trips,
  List<Trip>? allTrips,
  List<Trip>? stages,
  bool showOverview = false,
}) async {
  const routeKey = RouteKey(originStationId: '34', destinationStationId: '164');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routeTripsProvider.overrideWith((ref, routeKey) async => trips),
        legacyRouteModelProvider.overrideWith((ref, routeKey) async => model),
        myTripsProvider.overrideWith((ref) async => allTrips ?? trips),
        myTripStagesProvider.overrideWith((ref) async => stages ?? trips),
      ],
      child: MaterialApp(
        home: RouteHistoryScreen(
          routeKey: routeKey,
          selectedTripId: 'selected',
          showOverview: showOverview,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Trip _stage({
  required String id,
  required String originId,
  required String destinationId,
  required DateTime startedAt,
  required int durationSeconds,
  required double distanceMeters,
  String? tripCost,
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user-1',
    originStationId: originId,
    originStationName: '$originId - Estación $originId',
    destinationStationId: destinationId,
    destinationStationName: '$destinationId - Estación $destinationId',
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    isShared: true,
    directDistanceMeters: distanceMeters,
    tripCost: tripCost,
  );
}

LegacyRouteModel _model({
  required int displayedCount,
  int? totalCount,
  int outlierCount = 0,
}) {
  return LegacyRouteModel(
    originStationCode: '34',
    destinationStationCode: '164',
    originStationName: 'Jacinto Benavente',
    destinationStationName: 'Paseo de las Delicias',
    totalCount: totalCount ?? displayedCount + outlierCount,
    displayedCount: displayedCount,
    outlierCount: outlierCount,
    upperCutoffSeconds: 220,
    bestSeconds: 60,
    binEdges: const [60, 100, 140, 180, 220],
    binCounts: const [2, 3, 4, 1],
    firstTripAt: DateTime(2017, 1, 1),
    lastTripAt: DateTime(2022, 12, 31),
    modelFamily: 'empirical_histogram',
    modelVersion: 'test',
  );
}

Trip _trip(
  String id, {
  int durationSeconds = 120,
  double? distanceMeters,
  List<PitStop> pitStops = const [],
  String? bikeId,
  String? tripCost,
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user-1',
    originStationId: '34',
    originStationName: '34 - Jacinto Benavente',
    destinationStationId: '164',
    destinationStationName: '164 - Paseo de las Delicias',
    startedAt: DateTime(2026, 8, 2, 10),
    durationSeconds: durationSeconds,
    isShared: true,
    directDistanceMeters: distanceMeters,
    bikeId: bikeId,
    tripCost: tripCost,
    pitStops: pitStops,
  );
}

Future<String> _createTempDatabase({required int totalCount}) async {
  final file = File(
    '${Directory.systemTemp.createTempSync('legacy_model_test_').path}/legacy.sqlite',
  );
  final database = sqlite3.open(file.path);
  try {
    database.execute("""
      CREATE TABLE route_models (
        origin_station_code TEXT NOT NULL,
        destination_station_code TEXT NOT NULL,
        origin_station_name TEXT NOT NULL,
        destination_station_name TEXT NOT NULL,
        total_count INTEGER NOT NULL,
        displayed_count INTEGER NOT NULL,
        outlier_count INTEGER NOT NULL,
        upper_cutoff_seconds REAL NOT NULL,
        best_seconds REAL NOT NULL,
        bin_edges TEXT NOT NULL,
        bin_counts TEXT NOT NULL,
        first_trip_at TEXT NOT NULL,
        last_trip_at TEXT NOT NULL,
        model_family TEXT NOT NULL,
        model_version TEXT NOT NULL,
        PRIMARY KEY (origin_station_code, destination_station_code)
      );
      """);
    database.execute(
      """
      INSERT INTO route_models VALUES (
        '34', '164', 'Jacinto Benavente', 'Paseo de las Delicias',
        ?, 28, 2, 220.0, 60.0, '[60,100,140,180,220]', '[2,3,4,1]',
        '2023-01-01T00:00:00', '2023-12-31T00:00:00',
        'empirical_histogram', 'test'
      );
      """,
      [totalCount],
    );
  } finally {
    database.close();
  }
  return file.path;
}
