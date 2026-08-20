String? normalizeBikeId(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  if (!RegExp(r'^\d+$').hasMatch(raw)) {
    return raw;
  }
  final withoutLeadingZeros = raw.replaceFirst(RegExp(r'^0+'), '');
  return withoutLeadingZeros.isEmpty ? '0' : withoutLeadingZeros;
}
