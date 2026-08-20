import 'package:bicimad_social/app/app.dart';
import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/authentication/data/mock_bicimad_repository.dart';
import 'package:bicimad_social/features/trips/data/mock_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/presentation/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets('la lista construye de forma perezosa un historico grande', (
    tester,
  ) async {
    final trips = [
      for (var index = 0; index < 1000; index++)
        Trip(
          id: 'lazy-$index',
          externalId: 'lazy-$index',
          userId: 'user-1',
          originStationId: '1',
          originStationName: '1 - Origen',
          destinationStationId: '2',
          destinationStationName: '2 - Destino',
          startedAt: DateTime(2026, 1, 1).add(Duration(minutes: index)),
          durationSeconds: 600,
          isShared: true,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripsListView(trips: trips, avatarAsset: 'assets/avatar/1.png'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(TripCard).evaluate().length, lessThan(20));
    expect(find.byKey(const ValueKey('trip-list-item-lazy-999')), findsNothing);
  });

  testWidgets('muestra el precio rojo antes de la medalla superior', (
    tester,
  ) async {
    final trip = Trip(
      id: 'trip-card',
      externalId: 'trip-card',
      userId: 'user-1',
      originStationId: '1',
      originStationName: '1 - Origen',
      destinationStationId: '2',
      destinationStationName: '2 - Destino',
      startedAt: DateTime(2026, 8, 7, 10),
      durationSeconds: 600,
      isShared: true,
      directDistanceMeters: 1250,
      tripCost: '1.5',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripCard(
            trip: trip,
            isPersonalRecord: true,
            avatarAsset: 'assets/avatar/1.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.25 km'), findsOneWidget);
    expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    expect(find.text('-1,5 €'), findsOneWidget);
    expect(find.text('07/08/2026 10:00 - 10:10'), findsOneWidget);
    final price = find.byKey(const ValueKey('trip-price-pill-trip-card'));
    final medal = find.byKey(const ValueKey('personal-record-medal'));
    expect(price, findsOneWidget);
    expect(medal, findsOneWidget);
    expect(tester.getTopRight(price).dx, lessThan(tester.getTopLeft(medal).dx));
  });

  testWidgets('oculta el precio de la tarjeta cuando es cero', (tester) async {
    final trip = Trip(
      id: 'trip-card',
      externalId: 'trip-card',
      userId: 'user-1',
      originStationId: '1',
      originStationName: '1 - Origen',
      destinationStationId: '2',
      destinationStationName: '2 - Destino',
      startedAt: DateTime(2026, 8, 7, 10),
      durationSeconds: 600,
      isShared: true,
      directDistanceMeters: 1250,
      tripCost: '0.0',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripCard(
            trip: trip,
            isPersonalRecord: false,
            avatarAsset: 'assets/avatar/1.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.payments_outlined), findsNothing);
  });

  testWidgets('shows imported trips after simulated login', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadRepositoryProvider.overrideWithValue(MockBicimadRepository()),
          selectedAvatarProvider.overrideWith((ref) async {
            return 'assets/avatar/1.png';
          }),
          stationUsageProvider.overrideWith((ref) async {
            return const [];
          }),
          communityRepositoryProvider.overrideWithValue(
            MockCommunityRepository(),
          ),
          socialRepositoryProvider.overrideWithValue(FakeSocialRepository()),
          secureKeyValueStoreProvider.overrideWithValue(
            InMemorySecureKeyValueStore(),
          ),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'pablo@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('Entrar con MPass'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre visible'), findsWidgets);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('General'), findsWidgets);
    await tester.tap(find.text('Viajes').last);
    await tester.pumpAndSettle();

    expect(find.text('Mis viajes'), findsOneWidget);
    expect(find.textContaining('Manuel Becerra'), findsWidgets);
    expect(find.textContaining('Felipe II'), findsWidgets);
    expect(find.byKey(const ValueKey('personal-record-medal')), findsWidgets);
    expect(find.text('Record personal'), findsNothing);
  });

  testWidgets('tocar un viaje abre el historial dirigido de esa ruta', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadRepositoryProvider.overrideWithValue(MockBicimadRepository()),
          selectedAvatarProvider.overrideWith((ref) async {
            return 'assets/avatar/1.png';
          }),
          stationUsageProvider.overrideWith((ref) async {
            return const [];
          }),
          communityRepositoryProvider.overrideWithValue(
            MockCommunityRepository(),
          ),
          socialRepositoryProvider.overrideWithValue(FakeSocialRepository()),
          secureKeyValueStoreProvider.overrideWithValue(
            InMemorySecureKeyValueStore(),
          ),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'pablo@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('Entrar con MPass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Viajes').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TripCard).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Viaje'), findsWidgets);
    expect(find.textContaining('Manuel Becerra'), findsWidgets);
    expect(find.text('Datos del viaje'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-personal-context-card')),
      260,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu historial en esta ruta'), findsOneWidget);
    expect(find.text('Viajes'), findsOneWidget);
    expect(find.text('Ver en Rankings'), findsOneWidget);
    expect(find.text('Mis viajes entre estas estaciones'), findsNothing);
  });
}
