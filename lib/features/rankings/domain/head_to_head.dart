import 'route_key.dart';

enum HeadToHeadResult { win, draw, loss }

class HeadToHeadEntry {
  const HeadToHeadEntry({
    required this.routeKey,
    required this.originStationName,
    required this.destinationStationName,
    required this.currentDurationMilliseconds,
    required this.otherDurationMilliseconds,
  });

  final RouteKey routeKey;
  final String originStationName;
  final String destinationStationName;
  final int currentDurationMilliseconds;
  final int otherDurationMilliseconds;

  int get differenceMilliseconds =>
      otherDurationMilliseconds - currentDurationMilliseconds;

  HeadToHeadResult get result {
    if (differenceMilliseconds > 0) return HeadToHeadResult.win;
    if (differenceMilliseconds < 0) return HeadToHeadResult.loss;
    return HeadToHeadResult.draw;
  }
}

List<HeadToHeadEntry> orderHeadToHeadEntries(
  Iterable<HeadToHeadEntry> entries,
) {
  final wins = <HeadToHeadEntry>[];
  final draws = <HeadToHeadEntry>[];
  final losses = <HeadToHeadEntry>[];
  for (final entry in entries) {
    switch (entry.result) {
      case HeadToHeadResult.win:
        wins.add(entry);
      case HeadToHeadResult.draw:
        draws.add(entry);
      case HeadToHeadResult.loss:
        losses.add(entry);
    }
  }
  int compareDifference(HeadToHeadEntry a, HeadToHeadEntry b) =>
      b.differenceMilliseconds.compareTo(a.differenceMilliseconds);
  wins.sort(compareDifference);
  losses.sort(compareDifference);
  int compareRoute(HeadToHeadEntry a, HeadToHeadEntry b) {
    final origin = a.routeKey.originStationId.compareTo(
      b.routeKey.originStationId,
    );
    if (origin != 0) return origin;
    return a.routeKey.destinationStationId.compareTo(
      b.routeKey.destinationStationId,
    );
  }

  draws.sort(compareRoute);
  return List.unmodifiable([...wins, ...draws, ...losses]);
}

class HeadToHeadSummary {
  const HeadToHeadSummary({required this.entries});

  final List<HeadToHeadEntry> entries;

  int get wins => entries.where((e) => e.result == HeadToHeadResult.win).length;
  int get draws =>
      entries.where((e) => e.result == HeadToHeadResult.draw).length;
  int get losses =>
      entries.where((e) => e.result == HeadToHeadResult.loss).length;
}
