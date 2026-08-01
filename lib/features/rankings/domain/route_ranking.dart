import 'ranking_entry.dart';

class RouteRanking {
  const RouteRanking({
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.entries,
    required this.currentUserPosition,
    required this.totalUsers,
  });

  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final List<RankingEntry> entries;
  final int? currentUserPosition;
  final int totalUsers;
}
