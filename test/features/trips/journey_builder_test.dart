import 'package:bicimad_social/features/trips/domain/journey_builder.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = JourneyBuilder();

  test('fusiona etapas A-B-C con pit stop menor de dos minutos', () {
    final journeys = builder.buildJourneys([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300),
      _stage('bc', 'B', 'C', DateTime(2026, 8, 4, 10, 6), 420),
    ]);

    expect(journeys, hasLength(1));
    expect(journeys.single.originStationId, 'A');
    expect(journeys.single.destinationStationId, 'C');
    expect(journeys.single.durationSeconds, 780);
    expect(journeys.single.pitStops.single.stationId, 'B');
    expect(journeys.single.pitStops.single.durationSeconds, 60);
  });

  test('no fusiona A-B-A porque es vuelta al origen', () {
    final journeys = builder.buildJourneys([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300),
      _stage('ba', 'B', 'A', DateTime(2026, 8, 4, 10, 6), 420),
    ]);

    expect(journeys.map((trip) => trip.id), ['ba', 'ab']);
  });

  test('no fusiona si el pit stop dura dos minutos o mas', () {
    final journeys = builder.buildJourneys([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300),
      _stage('bc', 'B', 'C', DateTime(2026, 8, 4, 10, 7), 420),
    ]);

    expect(journeys.map((trip) => trip.id), ['bc', 'ab']);
  });

  test('descarta etapas con mismo origen y destino', () {
    final journeys = builder.buildJourneys([
      _stage('aa', 'A', 'A', DateTime(2026, 8, 4, 10), 300),
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 11), 300),
    ]);

    expect(journeys.map((trip) => trip.id), ['ab']);
  });

  test('descarta etapas a o desde ubicaciones invalidas de BiciMAD', () {
    final stages = [
      _stage(
        'invalid-origin',
        'X',
        'A',
        DateTime(2026, 8, 4, 9),
        300,
        originName: 'Bici mal anclada',
      ),
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300),
      _stage(
        'invalid-destination',
        'B',
        'Y',
        DateTime(2026, 8, 4, 10, 6),
        300,
        destinationName: 'Ubicación no permitida',
      ),
    ];

    expect(builder.buildJourneys(stages).map((trip) => trip.id), ['ab']);
    expect(builder.buildRankingTrips(stages).map((trip) => trip.id), ['ab']);
  });

  test('conserva datos por etapa y suma el precio con la misma bicicleta', () {
    final journeys = builder.buildJourneys([
      _stage(
        'ab',
        'A',
        'B',
        DateTime(2026, 8, 4, 10),
        300,
        bikeId: 'bike-fake-1',
        tripCost: '0.10',
      ),
      _stage(
        'bc',
        'B',
        'C',
        DateTime(2026, 8, 4, 10, 6),
        420,
        bikeId: 'bike-fake-1',
        tripCost: '0.20',
      ),
    ]);

    final journey = journeys.single;
    expect(journey.bikeId, 'bike-fake-1');
    expect(journey.tripCost, '0.30');
    expect(journey.stageDetails, hasLength(2));
    expect(journey.stageDetails.map((stage) => stage.sourceTripId), [
      'ab',
      'bc',
    ]);
    expect(journey.stageDetails.map((stage) => stage.tripCost), [
      '0.10',
      '0.20',
    ]);
  });

  test('representa varias bicicletas sin inventar una unica', () {
    final journeys = builder.buildJourneys([
      _stage(
        'ab',
        'A',
        'B',
        DateTime(2026, 8, 4, 10),
        300,
        bikeId: 'bike-fake-1',
        tripCost: '1.00',
      ),
      _stage(
        'bc',
        'B',
        'C',
        DateTime(2026, 8, 4, 10, 6),
        420,
        bikeId: 'bike-fake-2',
        tripCost: '2.00',
      ),
    ]);

    final journey = journeys.single;
    expect(journey.bikeId, isNull);
    expect(journey.hasMultipleBikes, isTrue);
    expect(journey.bikeIds, ['bike-fake-1', 'bike-fake-2']);
    expect(journey.tripCost, '3.00');
  });

  test('no calcula precio del journey si falta en alguna etapa', () {
    final journeys = builder.buildJourneys([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300, tripCost: '1.00'),
      _stage('bc', 'B', 'C', DateTime(2026, 8, 4, 10, 6), 420),
    ]);

    expect(journeys.single.tripCost, isNull);
  });

  test('genera todos los subviajes contiguos para Rankings', () {
    final rankingTrips = builder.buildRankingTrips([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300),
      _stage('bc', 'B', 'C', DateTime(2026, 8, 4, 10, 6), 420),
      _stage('cd', 'C', 'D', DateTime(2026, 8, 4, 10, 14), 360),
    ]);

    expect(
      rankingTrips
          .map(
            (trip) => '${trip.originStationId}->${trip.destinationStationId}',
          )
          .toSet(),
      {'A->B', 'B->C', 'C->D', 'A->C', 'B->D', 'A->D'},
    );
    expect(rankingTrips, hasLength(6));
  });

  test('calcula cada subviaje con sus etapas y pit stops concretos', () {
    final rankingTrips = builder.buildRankingTrips([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 300, tripCost: '0.10'),
      _stage(
        'bc',
        'B',
        'C',
        DateTime(2026, 8, 4, 10, 6),
        420,
        tripCost: '0.20',
      ),
      _stage(
        'cd',
        'C',
        'D',
        DateTime(2026, 8, 4, 10, 14),
        360,
        tripCost: '0.30',
      ),
    ]);

    final ac = rankingTrips.singleWhere(
      (trip) => trip.originStationId == 'A' && trip.destinationStationId == 'C',
    );

    expect(ac.durationSeconds, 780);
    expect(ac.tripCost, '0.30');
    expect(ac.stageIds, ['ab', 'bc']);
    expect(ac.pitStops.single.stationId, 'B');
    expect(ac.parentJourneyId, 'journey-ab-bc-cd');
    expect(ac.navigationOriginStationId, 'A');
    expect(ac.navigationDestinationStationId, 'D');
  });

  test(
    'mantiene identidad distinta para rutas repetidas dentro del journey',
    () {
      final rankingTrips = builder.buildRankingTrips([
        _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 60),
        _stage('bc-1', 'B', 'C', DateTime(2026, 8, 4, 10, 1, 30), 60),
        _stage('cd', 'C', 'D', DateTime(2026, 8, 4, 10, 3), 60),
        _stage('db', 'D', 'B', DateTime(2026, 8, 4, 10, 4, 30), 60),
        _stage('bc-2', 'B', 'C', DateTime(2026, 8, 4, 10, 6), 60),
      ]);

      final atomicBc = rankingTrips.where(
        (trip) =>
            trip.originStationId == 'B' &&
            trip.destinationStationId == 'C' &&
            trip.stageCount == 1,
      );

      expect(atomicBc, hasLength(2));
      expect(atomicBc.map((trip) => trip.id).toSet(), hasLength(2));
    },
  );

  test('no expone subviajes con el mismo origen y destino', () {
    final rankingTrips = builder.buildRankingTrips([
      _stage('ab', 'A', 'B', DateTime(2026, 8, 4, 10), 60),
      _stage('bc', 'B', 'C', DateTime(2026, 8, 4, 10, 1, 30), 60),
      _stage('cb', 'C', 'B', DateTime(2026, 8, 4, 10, 3), 60),
    ]);

    expect(
      rankingTrips.any(
        (trip) => trip.originStationId == trip.destinationStationId,
      ),
      isFalse,
    );
  });
}

Trip _stage(
  String id,
  String origin,
  String destination,
  DateTime startedAt,
  int durationSeconds, {
  String? bikeId,
  String? tripCost,
  String? originName,
  String? destinationName,
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user-1',
    originStationId: origin,
    originStationName: originName ?? 'Station $origin',
    destinationStationId: destination,
    destinationStationName: destinationName ?? 'Station $destination',
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    isShared: true,
    bikeId: bikeId,
    tripCost: tripCost,
  );
}
