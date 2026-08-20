import 'package:flutter/foundation.dart';

typedef RankingPerformanceSink = void Function(String message);

void logRankingPerformance(
  String event,
  Duration elapsed, {
  bool enabled = kDebugMode,
  RankingPerformanceSink? sink,
}) {
  if (!enabled) {
    return;
  }
  (sink ?? debugPrint)(
    '[RANKING_PERF] event=$event ms=${elapsed.inMilliseconds}',
  );
}
