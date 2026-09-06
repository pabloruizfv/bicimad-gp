const _durationAxisStepsSeconds = <double>[
  1,
  2,
  5,
  10,
  15,
  20,
  30,
  45,
  60,
  90,
  120,
  180,
  300,
  600,
  900,
  1200,
  1800,
  3600,
  7200,
  10800,
  14400,
  21600,
  28800,
  43200,
  86400,
];

List<double> durationAxisTicks(double startSeconds, double endSeconds) {
  if (!startSeconds.isFinite ||
      !endSeconds.isFinite ||
      endSeconds <= startSeconds) {
    return const [];
  }

  final targetStep = (endSeconds - startSeconds) / 4;
  double? selectedStep;
  var selectedScore = double.infinity;

  for (final step in _durationAxisStepsSeconds) {
    final count = _tickCount(startSeconds, endSeconds, step);
    if (count < 4 || count > 6) continue;
    final score = (step - targetStep).abs() / targetStep;
    if (score < selectedScore) {
      selectedStep = step;
      selectedScore = score;
    }
  }

  selectedStep ??= _durationAxisStepsSeconds.reduce((best, candidate) {
    final bestCount = _tickCount(startSeconds, endSeconds, best);
    final candidateCount = _tickCount(startSeconds, endSeconds, candidate);
    final bestDistance = (bestCount - 5).abs();
    final candidateDistance = (candidateCount - 5).abs();
    if (candidateDistance != bestDistance) {
      return candidateDistance < bestDistance ? candidate : best;
    }
    return (candidate - targetStep).abs() < (best - targetStep).abs()
        ? candidate
        : best;
  });

  final first = ((startSeconds / selectedStep) - 1e-9).ceil();
  final last = ((endSeconds / selectedStep) + 1e-9).floor();
  return [for (var index = first; index <= last; index++) index * selectedStep];
}

String formatDurationAxisTick(double seconds) {
  final totalSeconds = seconds.round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final remainingSeconds = totalSeconds % 60;

  if (hours > 0) {
    if (minutes == 0 && remainingSeconds == 0) return '$hours h';
    if (remainingSeconds == 0) return '$hours h $minutes min';
    return '$hours:${_two(minutes)}:${_two(remainingSeconds)}';
  }
  if (minutes > 0) {
    if (remainingSeconds == 0) return '$minutes min';
    return '$minutes:${_two(remainingSeconds)}';
  }
  return '$remainingSeconds s';
}

int _tickCount(double start, double end, double step) {
  final first = ((start / step) - 1e-9).ceil();
  final last = ((end / step) + 1e-9).floor();
  return last < first ? 0 : last - first + 1;
}

String _two(int value) => value.toString().padLeft(2, '0');
