class RankingEntry {
  const RankingEntry({
    required this.userId,
    required this.displayName,
    required this.bestDurationSeconds,
    required this.position,
    required this.isCurrentUser,
  });

  final String userId;
  final String displayName;
  final int bestDurationSeconds;
  final int position;
  final bool isCurrentUser;
}
