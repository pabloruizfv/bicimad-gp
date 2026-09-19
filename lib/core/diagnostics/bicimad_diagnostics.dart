import 'package:flutter/foundation.dart';

class BicimadDiagnostics {
  const BicimadDiagnostics._();

  static void Function(String? message, {int? wrapWidth}) output = debugPrint;

  static void log(
    String stage,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!kDebugMode) {
      return;
    }
    final buffer = StringBuffer('[BICIMAD_DIAG] stage=$stage event=$event');
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      buffer.write(' ${entry.key}=$value');
    }
    output(buffer.toString());
  }

  static void error(String stage, Object error) {
    log(stage, 'error', {'type': error.runtimeType});
  }

  static void resetOutput() {
    output = debugPrint;
  }
}
