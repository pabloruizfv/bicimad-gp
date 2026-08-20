String? canonicalStationCode({
  required String stationId,
  required String stationName,
}) {
  final codeFromName = extractPublicStationCode(stationName);
  if (codeFromName != null) {
    return codeFromName;
  }

  return normalizeStationCode(stationId);
}

String? extractPublicStationCode(String value) {
  final match = RegExp(
    r'''^\s*["']?\s*(\d+\s*[a-z]?)\s*-\s*.+$''',
    caseSensitive: false,
  ).firstMatch(value.trim());
  return normalizeStationCode(match?.group(1));
}

String? normalizeStationCode(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'^0*(\d+)\s*([a-z]?)$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }
  return '${int.parse(match.group(1)!)}${match.group(2)!.toLowerCase()}';
}
