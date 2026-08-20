String formatDurationSeconds(int durationSeconds) {
  final duration = Duration(seconds: durationSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${_two(minutes)}:${_two(seconds)}';
  }

  return '$minutes:${_two(seconds)}';
}

String formatReadableDurationSeconds(num durationSeconds) {
  final totalSeconds = durationSeconds.round();
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours h ${_two(minutes)} min ${_two(seconds)} s';
  }

  return '$minutes min ${_two(seconds)} s';
}

String formatCompactReadableDurationSeconds(num durationSeconds) {
  final totalSeconds = durationSeconds.round();
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return "${hours}h ${_two(minutes)}'";
  }

  return "$minutes' ${_two(seconds)}''";
}

String formatPrimeDurationSeconds(num durationSeconds) {
  final totalSeconds = durationSeconds.round();
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours}h ${_two(minutes)}′ ${_two(seconds)}″';
  }

  return '$minutes′ ${_two(seconds)}″';
}

String _two(int value) => value.toString().padLeft(2, '0');
