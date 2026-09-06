import '../../../core/utils/decimal_amount.dart';
import 'trip.dart';
import 'trip_eligibility.dart';

class JourneyBuilder {
  const JourneyBuilder({this.maxPitStop = const Duration(seconds: 119)});

  final Duration maxPitStop;

  List<Trip> buildJourneys(Iterable<Trip> stages) {
    final journeys = [
      for (final group in _groupStages(stages)) _buildJourney(group),
    ];
    return journeys..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  List<Trip> buildRankingTrips(Iterable<Trip> stages) {
    final rankingTrips = <Trip>[];
    for (final group in _groupStages(stages)) {
      final parentJourney = _buildJourney(group);
      for (var start = 0; start < group.length; start++) {
        for (var end = start + 1; end <= group.length; end++) {
          if (start == 0 && end == group.length) {
            rankingTrips.add(parentJourney);
            continue;
          }

          final selectedStages = group.sublist(start, end);
          if (selectedStages.first.originStationId ==
              selectedStages.last.destinationStationId) {
            continue;
          }
          rankingTrips.add(
            _buildJourney(selectedStages).copyWith(
              id: 'ranking-${parentJourney.id}-$start-${end - 1}',
              parentJourneyId: parentJourney.id,
              parentJourneyOriginStationId: parentJourney.originStationId,
              parentJourneyDestinationStationId:
                  parentJourney.destinationStationId,
            ),
          );
        }
      }
    }
    return rankingTrips..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  List<List<Trip>> _groupStages(Iterable<Trip> stages) {
    final validStages = stages.where(isCountableBicimadStage).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final groups = <List<Trip>>[];
    var index = 0;
    while (index < validStages.length) {
      final journeyStages = <Trip>[validStages[index]];
      index++;
      while (index < validStages.length) {
        final next = validStages[index];
        final lastStage = journeyStages.last;
        final gapSeconds = next.startedAt
            .difference(lastStage.endedAt)
            .inSeconds;
        final sameStation =
            lastStage.destinationStationId == next.originStationId;
        final isReturnToOrigin =
            journeyStages.first.originStationId == next.destinationStationId;
        if (gapSeconds < 0 ||
            gapSeconds > maxPitStop.inSeconds ||
            !sameStation ||
            isReturnToOrigin) {
          break;
        }
        journeyStages.add(next);
        index++;
      }
      groups.add(journeyStages);
    }
    return groups;
  }

  Trip _buildJourney(List<Trip> stages) {
    final pitStops = _buildPitStops(stages);
    if (stages.length == 1) {
      final stage = stages.single;
      return stage.copyWith(
        stageIds: [stage.id],
        pitStops: const [],
        stageDetails: [JourneyStageDetails.fromTrip(stage)],
      );
    }

    final first = stages.first;
    final last = stages.last;
    final durationSeconds = last.endedAt.difference(first.startedAt).inSeconds;
    final stageIds = [for (final stage in stages) stage.id];
    final externalIds = [for (final stage in stages) stage.externalId];
    final bikeIds = [for (final stage in stages) stage.bikeId];
    final completeBikeData = bikeIds.every((bikeId) => bikeId != null);
    final distinctBikeIds = bikeIds.whereType<String>().toSet();
    final journeyBikeId = completeBikeData && distinctBikeIds.length == 1
        ? distinctBikeIds.single
        : null;
    final journeyCost = sumDecimalAmounts([
      for (final stage in stages) stage.tripCost,
    ]);

    return Trip(
      id: 'journey-${stageIds.join('-')}',
      externalId: externalIds.join('+'),
      userId: first.userId,
      originStationId: first.originStationId,
      originStationName: first.originStationName,
      destinationStationId: last.destinationStationId,
      destinationStationName: last.destinationStationName,
      startedAt: first.startedAt,
      durationSeconds: durationSeconds,
      isShared: stages.every((stage) => stage.isShared),
      bikeId: journeyBikeId,
      tripCost: journeyCost,
      pitStops: pitStops,
      stageIds: stageIds,
      stageDetails: [
        for (final stage in stages) JourneyStageDetails.fromTrip(stage),
      ],
    );
  }

  List<PitStop> _buildPitStops(List<Trip> stages) {
    return [
      for (var index = 0; index < stages.length - 1; index++)
        PitStop(
          stationId: stages[index].destinationStationId,
          stationName: stages[index].destinationStationName,
          durationSeconds: stages[index + 1].startedAt
              .difference(stages[index].endedAt)
              .inSeconds,
          latitude: stages[index].destinationLatitude,
          longitude: stages[index].destinationLongitude,
        ),
    ];
  }
}
