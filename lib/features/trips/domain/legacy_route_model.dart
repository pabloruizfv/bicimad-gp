class LegacyRouteModel {
  const LegacyRouteModel({
    required this.originStationCode,
    required this.destinationStationCode,
    required this.originStationName,
    required this.destinationStationName,
    required this.totalCount,
    required this.displayedCount,
    required this.outlierCount,
    required this.upperCutoffSeconds,
    required this.bestSeconds,
    required this.binEdges,
    required this.binCounts,
    required this.firstTripAt,
    required this.lastTripAt,
    required this.modelFamily,
    required this.modelVersion,
  });

  final String originStationCode;
  final String destinationStationCode;
  final String originStationName;
  final String destinationStationName;
  final int totalCount;
  final int displayedCount;
  final int outlierCount;
  final double upperCutoffSeconds;
  final double bestSeconds;
  final List<double> binEdges;
  final List<int> binCounts;
  final DateTime firstTripAt;
  final DateTime lastTripAt;
  final String modelFamily;
  final String modelVersion;

  bool get canPlot {
    return displayedCount >= 5 &&
        modelFamily == 'empirical_histogram' &&
        bestSeconds.isFinite &&
        upperCutoffSeconds.isFinite &&
        upperCutoffSeconds > bestSeconds &&
        binCounts.isNotEmpty &&
        binEdges.length == binCounts.length + 1 &&
        _hasStrictlyIncreasingEdges;
  }

  List<HistogramPoint> smoothedDensityPoints() {
    if (!canPlot) {
      return const [];
    }

    final densities = <double>[];
    for (var index = 0; index < binCounts.length; index++) {
      final width = binEdges[index + 1] - binEdges[index];
      densities.add(
        width > 0 && displayedCount > 0
            ? binCounts[index] / (displayedCount * width)
            : 0,
      );
    }

    final smoothed = <double>[];
    for (var index = 0; index < densities.length; index++) {
      final previous = index == 0 ? densities[index] : densities[index - 1];
      final current = densities[index];
      final next = index == densities.length - 1
          ? densities[index]
          : densities[index + 1];
      smoothed.add((previous + current * 2 + next) / 4);
    }

    return [
      HistogramPoint(bestSeconds, 0),
      for (var index = 0; index < smoothed.length; index++)
        HistogramPoint(
          (binEdges[index] + binEdges[index + 1]) / 2,
          smoothed[index],
        ),
      HistogramPoint(upperCutoffSeconds, 0),
    ];
  }

  bool isAboveDisplayedRange(double seconds) {
    return canPlot && seconds > upperCutoffSeconds;
  }

  double? percentileForDuration(double seconds) {
    if (!canPlot || seconds <= bestSeconds) {
      return 0;
    }
    if (seconds > upperCutoffSeconds) {
      return null;
    }

    var cumulative = 0.0;
    for (var index = 0; index < binCounts.length; index++) {
      final start = binEdges[index];
      final end = binEdges[index + 1];
      final count = binCounts[index];
      if (seconds >= end) {
        cumulative += count;
        continue;
      }
      if (seconds > start) {
        final width = end - start;
        if (width > 0) {
          cumulative += count * ((seconds - start) / width).clamp(0, 1);
        }
      }
      break;
    }

    return (cumulative / displayedCount * 100).clamp(0, 100);
  }

  double? durationForPercentile(double percentile) {
    if (!canPlot || !percentile.isFinite) {
      return null;
    }
    final normalized = percentile.clamp(0, 100) / 100;
    if (normalized <= 0) {
      return bestSeconds;
    }
    if (normalized >= 1) {
      return upperCutoffSeconds;
    }

    final targetCount = displayedCount * normalized;
    var cumulative = 0.0;
    for (var index = 0; index < binCounts.length; index++) {
      final count = binCounts[index];
      final nextCumulative = cumulative + count;
      if (targetCount <= nextCumulative && count > 0) {
        final fraction = ((targetCount - cumulative) / count).clamp(0, 1);
        return binEdges[index] +
            (binEdges[index + 1] - binEdges[index]) * fraction;
      }
      cumulative = nextCumulative;
    }
    return upperCutoffSeconds;
  }

  bool get _hasStrictlyIncreasingEdges {
    for (var index = 1; index < binEdges.length; index++) {
      if (!binEdges[index].isFinite || binEdges[index] <= binEdges[index - 1]) {
        return false;
      }
    }
    return binEdges.first.isFinite;
  }
}

class HistogramPoint {
  const HistogramPoint(this.seconds, this.density);

  final double seconds;
  final double density;
}
