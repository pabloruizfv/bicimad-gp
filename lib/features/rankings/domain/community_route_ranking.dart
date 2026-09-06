enum CommunityPlacementTier { gold, silver, bronze, graphite }

class CommunityRouteCandidate {
  const CommunityRouteCandidate({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.avatarKey,
    required this.durationMilliseconds,
    required this.isCurrentUser,
    this.directDistanceMeters,
    this.startedAt,
  });

  final String userId;
  final String displayName;
  final String username;
  final String avatarKey;
  final int durationMilliseconds;
  final double? directDistanceMeters;
  final DateTime? startedAt;
  final bool isCurrentUser;
}

class CommunityRouteRankingEntry {
  const CommunityRouteRankingEntry({
    required this.position,
    required this.userId,
    required this.displayName,
    required this.username,
    required this.avatarKey,
    required this.durationMilliseconds,
    required this.isCurrentUser,
    this.directDistanceMeters,
    this.startedAt,
  });

  final int position;
  final String userId;
  final String displayName;
  final String username;
  final String avatarKey;
  final int durationMilliseconds;
  final double? directDistanceMeters;
  final DateTime? startedAt;
  final bool isCurrentUser;

  String get avatarAsset {
    final normalized = avatarKey.trim();
    return 'assets/avatar/${normalized.isEmpty ? '1.png' : normalized}';
  }

  double get durationSeconds => durationMilliseconds / 1000;

  double? get equivalentAverageSpeedKmh {
    final distance = directDistanceMeters;
    if (distance == null || durationMilliseconds <= 0) {
      return null;
    }
    return distance / durationSeconds * 3.6;
  }

  CommunityPlacementTier get tier => switch (position) {
    1 => CommunityPlacementTier.gold,
    2 => CommunityPlacementTier.silver,
    3 => CommunityPlacementTier.bronze,
    _ => CommunityPlacementTier.graphite,
  };
}

class CommunityRouteRanking {
  const CommunityRouteRanking({required this.entries});

  factory CommunityRouteRanking.fromCandidates(
    Iterable<CommunityRouteCandidate> candidates,
  ) {
    final bestByUser = <String, CommunityRouteCandidate>{};
    for (final candidate in candidates) {
      if (candidate.durationMilliseconds <= 0) {
        continue;
      }
      final current = bestByUser[candidate.userId];
      if (current == null ||
          candidate.durationMilliseconds < current.durationMilliseconds) {
        bestByUser[candidate.userId] = candidate;
      }
    }

    final ordered = bestByUser.values.toList(growable: false)
      ..sort(
        (first, second) =>
            first.durationMilliseconds.compareTo(second.durationMilliseconds),
      );
    final entries = <CommunityRouteRankingEntry>[];
    int? previousDuration;
    var position = 0;
    for (var index = 0; index < ordered.length; index++) {
      final candidate = ordered[index];
      if (previousDuration != candidate.durationMilliseconds) {
        position = index + 1;
        previousDuration = candidate.durationMilliseconds;
      }
      entries.add(
        CommunityRouteRankingEntry(
          position: position,
          userId: candidate.userId,
          displayName: candidate.displayName,
          username: candidate.username,
          avatarKey: candidate.avatarKey,
          durationMilliseconds: candidate.durationMilliseconds,
          directDistanceMeters: candidate.directDistanceMeters,
          startedAt: candidate.startedAt,
          isCurrentUser: candidate.isCurrentUser,
        ),
      );
    }
    return CommunityRouteRanking(entries: List.unmodifiable(entries));
  }

  final List<CommunityRouteRankingEntry> entries;

  CommunityRouteRankingEntry? get currentUserEntry {
    for (final entry in entries) {
      if (entry.isCurrentUser) {
        return entry;
      }
    }
    return null;
  }
}
