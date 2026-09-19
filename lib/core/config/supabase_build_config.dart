import 'dart:convert';

class SupabaseBuildConfig {
  const SupabaseBuildConfig({
    required this.url,
    required this.publishableKey,
    required this.projectRef,
  });

  factory SupabaseBuildConfig.fromEnvironment() {
    return const SupabaseBuildConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      projectRef: String.fromEnvironment('SUPABASE_PROJECT_REF'),
    );
  }

  final String url;
  final String publishableKey;
  final String projectRef;

  void ensureClientKey() {
    final key = publishableKey.trim();
    var unsafe = key.startsWith('sb_secret_');
    if (key.split('.').length == 3) {
      try {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(key.split('.')[1]))),
        );
        unsafe = claims is! Map || claims['role'] != 'anon';
      } on FormatException {
        unsafe = true;
      }
    }
    if (unsafe) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY debe ser una clave publicable o anon. '
        'Nunca uses claves secretas, service_role ni tokens de usuario en Flutter.',
      );
    }
  }

  bool get isComplete =>
      url.trim().isNotEmpty &&
      publishableKey.trim().isNotEmpty &&
      projectRef.trim().isNotEmpty;
}
