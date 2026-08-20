import 'package:bicimad_social/features/social/domain/profile_statistics.dart';
import 'package:bicimad_social/features/trips/domain/canonical_trip_statistics.dart';
import 'package:bicimad_social/features/trips/domain/journey_builder.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/shared/widgets/arcade_user_stats_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('origen igual a destino no cuenta y una etapa normal si', () {
    final journeys = const JourneyBuilder().buildJourneys([
      _stage('loop', 'A', 'A', DateTime(2026, 1, 1), 300),
      _stage('valid', 'A', 'B', DateTime(2026, 1, 2), 600),
    ]);

    final statistics = CanonicalTripStatistics.fromJourneys(journeys);

    expect(statistics.totalTrips, 1);
    expect(statistics.totalDurationSeconds, 600);
  });

  test('dos etapas con pit stop producen un unico journey canonico', () {
    final journeys = const JourneyBuilder().buildJourneys([
      _stage('ab', 'A', 'B', DateTime(2026, 1, 1, 10), 600),
      _stage('bc', 'B', 'C', DateTime(2026, 1, 1, 10, 11), 600),
    ]);

    final statistics = CanonicalTripStatistics.fromJourneys(journeys);

    expect(journeys, hasLength(1));
    expect(journeys.single.stageCount, 2);
    expect(statistics.totalTrips, 1);
    expect(statistics.totalDurationSeconds, 1260);
  });

  test('history span incluye dias sin viajes entre primero y ultimo', () {
    final statistics = CanonicalTripStatistics.fromJourneys([
      _stage('first', 'A', 'B', DateTime(2026, 1, 1, 20), 600),
      _stage('last', 'C', 'D', DateTime(2026, 1, 10, 8), 600),
    ]);

    expect(statistics.distinctTripDays, 2);
    expect(statistics.historySpanDays, 10);
  });

  test('primer y ultimo journey en el mismo dia producen un dia', () {
    final statistics = CanonicalTripStatistics.fromJourneys([
      _stage('first', 'A', 'B', DateTime(2026, 1, 1, 8), 600),
      _stage('last', 'C', 'D', DateTime(2026, 1, 1, 20), 600),
    ]);

    expect(statistics.historySpanDays, 1);
  });

  test('tarjeta local y social reciben exactamente las mismas metricas', () {
    final local = CanonicalTripStatistics.fromJourneys([
      _stage('first', 'A', 'B', DateTime(2026, 1, 1, 8), 600, distance: 1200),
      _stage('last', 'C', 'D', DateTime(2026, 1, 10, 20), 900, distance: 1800),
    ]);
    final social = ProfileStatistics(
      totalTrips: local.totalTrips,
      historySpanDays: local.historySpanDays,
      distinctTripDays: local.distinctTripDays,
      totalDurationSeconds: local.totalDurationSeconds,
      totalDistanceMeters: local.totalDistanceMeters,
      equivalentAverageSpeedKmh: local.equivalentAverageSpeedKmh,
      tripsWithDistance: local.tripsWithDistance,
    );

    final localCard = ProfileStatsCardData.fromStatistics(local);
    final socialCard = ProfileStatsCardData.fromStatistics(social);

    expect(socialCard.totalTrips, localCard.totalTrips);
    expect(socialCard.historySpanDays, localCard.historySpanDays);
    expect(socialCard.totalDurationSeconds, localCard.totalDurationSeconds);
    expect(socialCard.totalDistanceMeters, localCard.totalDistanceMeters);
    expect(
      socialCard.equivalentAverageSpeedKmh,
      localCard.equivalentAverageSpeedKmh,
    );
    expect(socialCard.tripsWithDistance, localCard.tripsWithDistance);
  });
}

Trip _stage(
  String id,
  String origin,
  String destination,
  DateTime startedAt,
  int durationSeconds, {
  double? distance,
}) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user',
    originStationId: origin,
    originStationName: origin,
    destinationStationId: destination,
    destinationStationName: destination,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    isShared: true,
    directDistanceMeters: distance,
  );
}
