import 'package:bicimad_social/features/trips/data/local_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/journey_builder.dart';
import 'package:bicimad_social/features/trips/domain/route_statistics.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/stations/data/station_catalog_repository.dart';
import 'package:bicimad_social/features/stations/domain/station.dart';
import 'package:bicimad_social/features/stations/domain/station_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  group('LocalCommunityRepository.getTripsForRoute', () {
    test('A -> B solo contiene viajes A -> B y excluye B -> A', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('ab-1', 'A', 'B', DateTime(2026, 8, 2, 10), 600),
        _trip('ba-1', 'B', 'A', DateTime(2026, 8, 2, 11), 500),
      ]);

      final trips = await repository.getTripsForRoute(
        originStationId: 'A',
        destinationStationId: 'B',
      );

      expect(trips.map((trip) => trip.id), ['ab-1']);
    });

    test('compara por ID y no por nombre visible', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip(
          'ab-1',
          'A',
          'B',
          DateTime(2026, 8, 2, 10),
          600,
          originName: 'Misma estacion',
          destinationName: 'Otra estacion',
        ),
        _trip(
          'xy-1',
          'X',
          'Y',
          DateTime(2026, 8, 2, 11),
          500,
          originName: 'Misma estacion',
          destinationName: 'Otra estacion',
        ),
      ]);

      final trips = await repository.getTripsForRoute(
        originStationId: 'A',
        destinationStationId: 'B',
      );

      expect(trips.map((trip) => trip.id), ['ab-1']);
    });

    test('ordena resultados del mas reciente al mas antiguo', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('old', 'A', 'B', DateTime(2026, 8, 1, 10), 600),
        _trip('new', 'A', 'B', DateTime(2026, 8, 2, 10), 500),
      ]);

      final trips = await repository.getTripsForRoute(
        originStationId: 'A',
        destinationStationId: 'B',
      );

      expect(trips.map((trip) => trip.id), ['new', 'old']);
    });

    test(
      'sincronizacion conserva viajes antiguos y evita duplicados',
      () async {
        final repository = LocalCommunityRepository();
        await repository.createOrRecoverUser(externalUserId: 'user-1');
        final oldTrip = _trip('old', 'A', 'B', DateTime(2026, 8, 1), 600);
        final newTrip = _trip('new', 'A', 'B', DateTime(2026, 8, 2), 500);

        await repository.replaceMyTrips([oldTrip]);
        await repository.replaceMyTrips([newTrip]);
        await repository.replaceMyTrips([newTrip]);

        final trips = await repository.getMyTrips();

        expect(trips.map((trip) => trip.id), ['new', 'old']);
        expect(trips.map((trip) => trip.externalId).toSet(), {'old', 'new'});
        expect(trips, hasLength(2));
      },
    );

    test('registra periodos de cobertura por solape de IDs', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      final oldTrip = _trip('old', 'A', 'B', DateTime(2026, 8, 1), 600);
      final newTrip = _trip('new', 'A', 'B', DateTime(2026, 8, 3), 500);
      final unrelated = _trip('other', 'A', 'B', DateTime(2026, 8, 10), 500);

      await repository.replaceMyTrips([oldTrip]);
      await repository.replaceMyTrips([oldTrip, newTrip]);
      await repository.replaceMyTrips([unrelated]);

      final intervals = await repository.getCoverageIntervals();

      expect(intervals, hasLength(2));
      expect(intervals.first.start, oldTrip.startedAt);
      expect(intervals.first.end, newTrip.startedAt);
      expect(intervals.last.start, unrelated.startedAt);
    });

    test('enriquece viajes almacenados con catalogo local', () async {
      final store = InMemorySecureKeyValueStore();
      final repository = LocalCommunityRepository(
        store: store,
        stationCatalogRepository: _FakeStationCatalogRepository(),
      );
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('t1', 'A', 'B', DateTime(2026, 8, 1), 600),
      ]);

      final recreated = LocalCommunityRepository(
        store: store,
        stationCatalogRepository: _FakeStationCatalogRepository(),
      );
      await recreated.createOrRecoverUser(externalUserId: 'user-1');
      final trips = await recreated.getMyTrips();

      expect(trips.single.directDistanceMeters, isNotNull);
      expect(trips.single.originLatitude, 40.0);
    });

    test('el historico persiste al recrear el repositorio local', () async {
      final store = InMemorySecureKeyValueStore();
      final firstRepository = LocalCommunityRepository(store: store);
      await firstRepository.createOrRecoverUser(externalUserId: 'user-1');
      await firstRepository.replaceMyTrips([
        _trip('old', 'A', 'B', DateTime(2026, 8, 1), 600),
        _trip('new', 'A', 'B', DateTime(2026, 8, 2), 500),
      ]);

      final recreatedRepository = LocalCommunityRepository(store: store);
      await recreatedRepository.createOrRecoverUser(externalUserId: 'user-1');
      await recreatedRepository.replaceMyTrips([
        _trip('new', 'A', 'B', DateTime(2026, 8, 2), 500),
      ]);

      final trips = await recreatedRepository.getMyTrips();

      expect(trips.map((trip) => trip.id), ['new', 'old']);
      expect(trips, hasLength(2));
    });

    test(
      'una nueva importacion enriquece bicicleta y precio sin borrarlos con null',
      () async {
        final store = InMemorySecureKeyValueStore();
        final repository = LocalCommunityRepository(store: store);
        await repository.createOrRecoverUser(externalUserId: 'user-1');
        await repository.replaceMyTrips([
          _trip('trip-1', 'A', 'B', DateTime(2026, 8, 1), 600),
        ]);
        await repository.replaceMyTrips([
          _trip(
            'trip-1',
            'A',
            'B',
            DateTime(2026, 8, 1),
            600,
            bikeId: 'bike-fake-1',
            tripCost: '1.2300',
          ),
        ]);
        await repository.replaceMyTrips([
          _trip('trip-1', 'A', 'B', DateTime(2026, 8, 1), 600),
        ]);

        final recreated = LocalCommunityRepository(store: store);
        await recreated.createOrRecoverUser(externalUserId: 'user-1');
        final stages = await recreated.getMyStages();

        expect(stages, hasLength(1));
        expect(stages.single.bikeId, 'bike-fake-1');
        expect(stages.single.tripCost, '1.2300');
      },
    );

    test(
      'clear cierra el usuario activo pero conserva viajes historicos',
      () async {
        final store = InMemorySecureKeyValueStore();
        final repository = LocalCommunityRepository(store: store);
        await repository.createOrRecoverUser(externalUserId: 'user-1');
        await repository.replaceMyTrips([
          _trip('old', 'A', 'B', DateTime(2026, 8, 1), 600),
        ]);

        await repository.clear();
        await repository.createOrRecoverUser(externalUserId: 'user-1');

        final trips = await repository.getMyTrips();

        expect(trips.map((trip) => trip.id), ['old']);
      },
    );

    test('expone viajes combinados y no etapas consecutivas', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('ab', 'A', 'B', DateTime(2026, 8, 2, 10), 300),
        _trip('bc', 'B', 'C', DateTime(2026, 8, 2, 10, 6), 420),
      ]);

      final trips = await repository.getMyTrips();

      expect(trips, hasLength(1));
      expect(trips.single.originStationId, 'A');
      expect(trips.single.destinationStationId, 'C');
      expect(trips.single.pitStops.single.durationSeconds, 60);
    });

    test('Rankings expone etapas y todos los subviajes contiguos', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('ab', 'A', 'B', DateTime(2026, 8, 2, 10), 300),
        _trip('bc', 'B', 'C', DateTime(2026, 8, 2, 10, 6), 420),
        _trip('cd', 'C', 'D', DateTime(2026, 8, 2, 10, 14), 360),
      ]);

      final rankingTrips = await repository.getMyRankingTrips();
      final mainTrips = await repository.getMyTrips();
      final acTrips = await repository.getTripsForRoute(
        originStationId: 'A',
        destinationStationId: 'C',
      );
      final bdTrips = await repository.getTripsForRoute(
        originStationId: 'B',
        destinationStationId: 'D',
      );

      expect(mainTrips, hasLength(1));
      expect(
        mainTrips.single.matchesRoute(
          originStationId: 'A',
          destinationStationId: 'D',
        ),
        isTrue,
      );
      expect(rankingTrips, hasLength(6));
      expect(acTrips.single.stageIds, ['ab', 'bc']);
      expect(bdTrips.single.stageIds, ['bc', 'cd']);
      expect(acTrips.single.navigationJourneyId, mainTrips.single.id);
    });

    test('memoiza journeys hasta que cambian las etapas', () async {
      final builder = _CountingJourneyBuilder();
      final repository = LocalCommunityRepository(journeyBuilder: builder);
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('first', 'A', 'B', DateTime(2026, 8, 1), 600),
      ]);

      await repository.getMyTrips();
      await repository.getMyTrips();
      await repository.getTripsForRoute(
        originStationId: 'A',
        destinationStationId: 'B',
      );
      expect(builder.buildCount, 1);

      await repository.upsertMyTripPage([
        _trip('second', 'A', 'B', DateTime(2026, 8, 2), 500),
      ]);
      await repository.getMyTrips();
      expect(builder.buildCount, 2);
    });

    test('descarta etapas con misma estacion de origen y destino', () async {
      final repository = LocalCommunityRepository();
      await repository.createOrRecoverUser(externalUserId: 'user-1');
      await repository.replaceMyTrips([
        _trip('aa', 'A', 'A', DateTime(2026, 8, 2, 10), 300),
        _trip('ab', 'A', 'B', DateTime(2026, 8, 2, 11), 420),
      ]);

      final trips = await repository.getMyTrips();

      expect(trips.map((trip) => trip.id), ['ab']);
    });
  });

  group('RouteStatistics', () {
    test('calcula total, mejor, media, mediana impar y ultimo valido', () {
      final statistics = RouteStatistics.fromTrips([
        _trip('t1', 'A', 'B', DateTime(2026, 8, 1, 8), 600),
        _trip('t2', 'A', 'B', DateTime(2026, 8, 2, 8), 540),
        _trip('t3', 'A', 'B', DateTime(2026, 8, 3, 8), 660),
      ]);

      expect(statistics.totalTrips, 3);
      expect(statistics.bestDurationSeconds, 540);
      expect(statistics.averageDurationSeconds, 600);
      expect(statistics.medianDurationSeconds, 600);
      expect(statistics.latestDurationSeconds, 660);
      expect(
        statistics.isBestTrip(
          _trip('t2', 'A', 'B', DateTime(2026, 8, 2, 8), 540),
        ),
        isTrue,
      );
    });

    test('calcula mediana par como media de los dos valores centrales', () {
      final statistics = RouteStatistics.fromTrips([
        _trip('t1', 'A', 'B', DateTime(2026, 8, 1), 500),
        _trip('t2', 'A', 'B', DateTime(2026, 8, 2), 600),
        _trip('t3', 'A', 'B', DateTime(2026, 8, 3), 700),
        _trip('t4', 'A', 'B', DateTime(2026, 8, 4), 800),
      ]);

      expect(statistics.medianDurationSeconds, 650);
    });

    test('ignora duraciones cero o negativas en estadisticas', () {
      final statistics = RouteStatistics.fromTrips([
        _trip('zero', 'A', 'B', DateTime(2026, 8, 3), 0),
        _trip('negative', 'A', 'B', DateTime(2026, 8, 4), -10),
        _trip('valid', 'A', 'B', DateTime(2026, 8, 1), 500),
      ]);

      expect(statistics.totalTrips, 3);
      expect(statistics.validTripCount, 1);
      expect(statistics.bestDurationSeconds, 500);
      expect(statistics.averageDurationSeconds, 500);
      expect(statistics.medianDurationSeconds, 500);
      expect(statistics.latestDurationSeconds, 500);
    });
  });
}

class _CountingJourneyBuilder extends JourneyBuilder {
  int buildCount = 0;

  @override
  List<Trip> buildJourneys(Iterable<Trip> stages) {
    buildCount += 1;
    return super.buildJourneys(stages);
  }
}

class _FakeStationCatalogRepository implements StationCatalogRepository {
  final StationCatalog catalog = StationCatalog(
    stations: const [
      Station(
        id: 'A',
        publicCode: '1',
        name: 'Origen',
        latitude: 40.0,
        longitude: -3.0,
      ),
      Station(
        id: 'B',
        publicCode: '2',
        name: 'Destino',
        latitude: 40.1,
        longitude: -3.1,
      ),
    ],
    updatedAt: DateTime(2026, 8, 2),
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

Trip _trip(
  String id,
  String originStationId,
  String destinationStationId,
  DateTime startedAt,
  int durationSeconds, {
  String originName = 'Origen',
  String destinationName = 'Destino',
  String? bikeId,
  String? tripCost,
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user-1',
    originStationId: originStationId,
    originStationName: originName,
    destinationStationId: destinationStationId,
    destinationStationName: destinationName,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    isShared: true,
    bikeId: bikeId,
    tripCost: tripCost,
  );
}
