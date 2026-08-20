import 'dart:async';

import '../../../core/errors/app_exception.dart';
import '../../authentication/domain/bicimad_repository.dart';
import '../../authentication/domain/mpass_session.dart';
import '../domain/community_repository.dart';
import '../domain/trip.dart';
import '../domain/trip_history_sync.dart';

class TripHistorySyncService {
  TripHistorySyncService({
    required this.bicimadRepository,
    required this.communityRepository,
    this.pageSize = 30,
    this.maxPages = 200,
    this.knownBoundaryPageCount = 2,
    this.transientRetries = 1,
    this.retryDelay = const Duration(seconds: 2),
    this.pageDelay = const Duration(milliseconds: 300),
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  }) : _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final BicimadRepository bicimadRepository;
  final CommunityRepository communityRepository;
  final int pageSize;
  final int maxPages;
  final int knownBoundaryPageCount;
  final int transientRetries;
  final Duration retryDelay;
  final Duration pageDelay;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

  Future<TripHistorySyncResult> synchronize(
    MpassSession session, {
    void Function(TripHistorySyncProgress progress)? onProgress,
    Future<void> Function(List<Trip> trips)? onPagePersisted,
  }) async {
    final previousState = await communityRepository.getTripHistorySyncState();
    final knownBefore = await communityRepository.getKnownSourceTripIds();
    final isFullHistoryScan = !previousState.historyExhausted;
    final seenThisRun = <String>{};
    var consecutiveKnownPages = 0;
    var pagesFetched = 0;
    var tripsProcessed = 0;
    var overlapsKnownTrips = false;
    DateTime? oldestImportedAt;
    DateTime? newestImportedAt;

    Future<void> recordInterrupted() {
      return communityRepository.recordTripHistoryImport(
        TripHistoryImportRecord(
          state: TripHistorySyncState(
            historyExhausted: previousState.historyExhausted,
            lastRunStatus: TripHistoryRunStatus.interrupted,
            updatedAt: _now(),
          ),
          overlapsKnownTrips: overlapsKnownTrips,
          oldestImportedAt: oldestImportedAt,
          newestImportedAt: newestImportedAt,
        ),
      );
    }

    try {
      for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
        final page = pageIndex == 0 ? null : pageIndex;
        final trips = await _fetchPageWithRetry(session, page: page);
        pagesFetched += 1;

        final pageIds = {for (final trip in trips) trip.externalId};
        if (pageIds.isNotEmpty && pageIds.every(seenThisRun.contains)) {
          await recordInterrupted();
          throw const TripHistorySyncException(
            'BiciMAD ha repetido una pagina completa del historico.',
          );
        }

        final uniquePageTrips = <Trip>[];
        for (final trip in trips) {
          if (seenThisRun.add(trip.externalId)) {
            uniquePageTrips.add(trip);
          }
          if (knownBefore.contains(trip.externalId)) {
            overlapsKnownTrips = true;
          }
          oldestImportedAt = _earlier(oldestImportedAt, trip.startedAt);
          newestImportedAt = _later(newestImportedAt, trip.startedAt);
        }

        if (uniquePageTrips.isNotEmpty) {
          await communityRepository.upsertMyTripPage(uniquePageTrips);
          await onPagePersisted?.call(uniquePageTrips);
          tripsProcessed += uniquePageTrips.length;
        }
        onProgress?.call(
          TripHistorySyncProgress(
            pagesFetched: pagesFetched,
            tripsProcessed: tripsProcessed,
            isFullHistoryScan: isFullHistoryScan,
          ),
        );

        if (trips.length < pageSize) {
          final completedState = TripHistorySyncState(
            historyExhausted: true,
            lastRunStatus: TripHistoryRunStatus.completed,
            updatedAt: _now(),
          );
          await communityRepository.recordTripHistoryImport(
            TripHistoryImportRecord(
              state: completedState,
              overlapsKnownTrips: overlapsKnownTrips,
              oldestImportedAt: oldestImportedAt,
              newestImportedAt: newestImportedAt,
            ),
          );
          return TripHistorySyncResult(
            pagesFetched: pagesFetched,
            tripsProcessed: tripsProcessed,
            stopReason: TripHistoryStopReason.historyExhausted,
            historyExhausted: true,
          );
        }

        final isCompletelyKnownFullPage =
            !isFullHistoryScan &&
            trips.length == pageSize &&
            pageIds.length == pageSize &&
            pageIds.every(knownBefore.contains);
        consecutiveKnownPages = isCompletelyKnownFullPage
            ? consecutiveKnownPages + 1
            : 0;
        if (consecutiveKnownPages >= knownBoundaryPageCount) {
          final completedState = TripHistorySyncState(
            historyExhausted: true,
            lastRunStatus: TripHistoryRunStatus.completed,
            updatedAt: _now(),
          );
          await communityRepository.recordTripHistoryImport(
            TripHistoryImportRecord(
              state: completedState,
              overlapsKnownTrips: true,
              oldestImportedAt: oldestImportedAt,
              newestImportedAt: newestImportedAt,
            ),
          );
          return TripHistorySyncResult(
            pagesFetched: pagesFetched,
            tripsProcessed: tripsProcessed,
            stopReason: TripHistoryStopReason.knownHistoryBoundary,
            historyExhausted: true,
          );
        }
        if (pageDelay > Duration.zero) {
          await _delay(pageDelay);
        }
      }

      await recordInterrupted();
      throw const TripHistorySyncException(
        'La sincronizacion alcanzo su limite de seguridad.',
      );
    } on TripHistorySyncException {
      rethrow;
    } on Object {
      await recordInterrupted();
      rethrow;
    }
  }

  Future<List<Trip>> _fetchPageWithRetry(
    MpassSession session, {
    required int? page,
  }) async {
    var retries = 0;
    while (true) {
      try {
        return await bicimadRepository.fetchTrips(session, page: page);
      } on NetworkException {
        if (retries >= transientRetries) {
          rethrow;
        }
        retries += 1;
        await _delay(retryDelay);
      }
    }
  }

  DateTime _earlier(DateTime? current, DateTime candidate) {
    return current == null || candidate.isBefore(current) ? candidate : current;
  }

  DateTime _later(DateTime? current, DateTime candidate) {
    return current == null || candidate.isAfter(current) ? candidate : current;
  }
}

class TripHistorySyncException extends AppException {
  const TripHistorySyncException(super.message);
}
