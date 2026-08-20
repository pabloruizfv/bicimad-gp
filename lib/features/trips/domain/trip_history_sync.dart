enum TripHistoryRunStatus { unexplored, completed, interrupted }

class TripHistorySyncState {
  const TripHistorySyncState({
    required this.historyExhausted,
    required this.lastRunStatus,
    this.updatedAt,
  });

  const TripHistorySyncState.initial()
    : historyExhausted = false,
      lastRunStatus = TripHistoryRunStatus.unexplored,
      updatedAt = null;

  final bool historyExhausted;
  final TripHistoryRunStatus lastRunStatus;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
    'historyExhausted': historyExhausted,
    'lastRunStatus': lastRunStatus.name,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  static TripHistorySyncState fromJson(Map<String, Object?> json) {
    final status = TripHistoryRunStatus.values.where(
      (value) => value.name == json['lastRunStatus'],
    );
    return TripHistorySyncState(
      historyExhausted: json['historyExhausted'] == true,
      lastRunStatus: status.isEmpty
          ? TripHistoryRunStatus.unexplored
          : status.first,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class TripHistoryImportRecord {
  const TripHistoryImportRecord({
    required this.state,
    required this.overlapsKnownTrips,
    this.oldestImportedAt,
    this.newestImportedAt,
  });

  final TripHistorySyncState state;
  final bool overlapsKnownTrips;
  final DateTime? oldestImportedAt;
  final DateTime? newestImportedAt;
}

class TripHistorySyncProgress {
  const TripHistorySyncProgress({
    required this.pagesFetched,
    required this.tripsProcessed,
    required this.isFullHistoryScan,
  });

  final int pagesFetched;
  final int tripsProcessed;
  final bool isFullHistoryScan;
}

enum TripHistoryStopReason { historyExhausted, knownHistoryBoundary }

class TripHistorySyncResult {
  const TripHistorySyncResult({
    required this.pagesFetched,
    required this.tripsProcessed,
    required this.stopReason,
    required this.historyExhausted,
  });

  final int pagesFetched;
  final int tripsProcessed;
  final TripHistoryStopReason stopReason;
  final bool historyExhausted;
}
