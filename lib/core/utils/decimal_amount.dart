String? normalizeDecimalAmount(Object? value) {
  if (value == null) {
    return null;
  }
  final raw = switch (value) {
    int() => value.toString(),
    double() when value.isFinite => value.toString(),
    String() => value.trim().replaceAll(',', '.'),
    _ => throw const FormatException('Invalid decimal amount'),
  };
  if (raw.isEmpty) {
    return null;
  }
  final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(raw);
  if (match == null) {
    throw const FormatException('Invalid decimal amount');
  }
  final fraction = match.group(3);
  final unsignedInteger = BigInt.parse(match.group(2)!);
  final integer = unsignedInteger.toString();
  final isZero =
      unsignedInteger == BigInt.zero &&
      (fraction == null || RegExp(r'^0+$').hasMatch(fraction));
  final sign = match.group(1) == '-' && !isZero ? '-' : '';
  return fraction == null ? '$sign$integer' : '$sign$integer.$fraction';
}

String? sumDecimalAmounts(Iterable<String?> values) {
  final parsed = <_DecimalParts>[];
  for (final value in values) {
    final normalized = normalizeDecimalAmount(value);
    if (normalized == null) {
      return null;
    }
    parsed.add(_DecimalParts.parse(normalized));
  }
  if (parsed.isEmpty) {
    return null;
  }
  final scale = parsed.fold<int>(
    0,
    (maximum, amount) => amount.scale > maximum ? amount.scale : maximum,
  );
  final total = parsed.fold<BigInt>(BigInt.zero, (sum, amount) {
    return sum + amount.units * _powerOfTen(scale - amount.scale);
  });
  return _formatUnits(total, scale);
}

String formatDecimalEuros(String? value) {
  final normalized = normalizeDecimalAmount(value);
  if (normalized == null) {
    return 'No disponible';
  }
  return '${normalized.replaceAll('.', ',')} €';
}

bool isPositiveDecimalAmount(String? value) {
  try {
    final normalized = normalizeDecimalAmount(value);
    if (normalized == null || normalized.startsWith('-')) {
      return false;
    }
    return normalized.runes.any(
      (character) => character >= 49 && character <= 57,
    );
  } on FormatException {
    return false;
  }
}

class _DecimalParts {
  const _DecimalParts({required this.units, required this.scale});

  factory _DecimalParts.parse(String value) {
    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final parts = unsigned.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    final units = BigInt.parse('${parts[0]}$fraction');
    return _DecimalParts(
      units: negative ? -units : units,
      scale: fraction.length,
    );
  }

  final BigInt units;
  final int scale;
}

BigInt _powerOfTen(int exponent) => BigInt.from(10).pow(exponent);

String _formatUnits(BigInt units, int scale) {
  final negative = units.isNegative;
  final digits = units.abs().toString().padLeft(scale + 1, '0');
  final sign = negative ? '-' : '';
  if (scale == 0) {
    return '$sign$digits';
  }
  final split = digits.length - scale;
  return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
}
