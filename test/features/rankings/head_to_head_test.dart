import 'package:bicimad_social/features/rankings/domain/head_to_head.dart';
import 'package:bicimad_social/features/rankings/domain/route_key.dart';
import 'package:flutter_test/flutter_test.dart';

HeadToHeadEntry entry(String origin, String destination, int mine, int theirs) {
  return HeadToHeadEntry(
    routeKey: RouteKey(
      originStationId: origin,
      destinationStationId: destination,
    ),
    originStationName: origin,
    destinationStationName: destination,
    currentDurationMilliseconds: mine,
    otherDurationMilliseconds: theirs,
  );
}

void main() {
  test('counts wins, draws and losses using exact milliseconds', () {
    final summary = HeadToHeadSummary(
      entries: [
        entry('a', 'b', 600000, 660000),
        entry('b', 'c', 480000, 450000),
        entry('c', 'd', 420000, 420000),
      ],
    );

    expect(summary.wins, 1);
    expect(summary.draws, 1);
    expect(summary.losses, 1);
  });

  test(
    'keeps directed routes separate and orders the continuous result list',
    () {
      final ordered = orderHeadToHeadEntries([
        entry('a', 'b', 600000, 660000),
        entry('b', 'a', 605000, 600000),
        entry('c', 'd', 700000, 700000),
        entry('e', 'f', 700000, 650000),
        entry('g', 'h', 800000, 850000),
      ]);

      expect(ordered.map((e) => e.routeKey.originStationId), [
        'a',
        'g',
        'c',
        'b',
        'e',
      ]);
      expect(ordered[0].differenceMilliseconds, 60000);
      expect(ordered[1].differenceMilliseconds, 50000);
      expect(ordered[2].result, HeadToHeadResult.draw);
      expect(ordered[3].differenceMilliseconds, -5000);
      expect(ordered[4].differenceMilliseconds, -50000);
    },
  );

  test('does not round away a real millisecond difference', () {
    final faster = entry('a', 'b', 411231, 411842);
    expect(faster.result, HeadToHeadResult.win);
    expect(faster.differenceMilliseconds, 611);
  });
}
