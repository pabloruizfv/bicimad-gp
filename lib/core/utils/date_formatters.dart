String formatShortDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String formatShortDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

String _two(int value) => value.toString().padLeft(2, '0');
