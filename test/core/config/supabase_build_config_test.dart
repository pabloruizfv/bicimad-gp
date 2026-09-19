import 'dart:convert';

import 'package:bicimad_social/core/config/supabase_build_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SupabaseBuildConfig config(String key) => SupabaseBuildConfig(
    url: 'https://example.invalid',
    publishableKey: key,
    projectRef: 'example',
  );

  String jwt(String role) =>
      '${base64Url.encode(utf8.encode('{}'))}.'
      '${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.'
      'test-signature';

  test('accepts public keys and legacy anon keys', () {
    config('sb_publishable_test').ensureClientKey();
    config(jwt('anon')).ensureClientKey();
    config('').ensureClientKey();
  });

  test('rejects server keys and user JWTs without echoing the value', () {
    for (final key in [
      'sb_${'secret_test-do-not-disclose'}',
      jwt('service_role'),
      jwt('authenticated'),
      'invalid.invalid.invalid',
    ]) {
      expect(
        () => config(key).ensureClientKey(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains(key)),
          ),
        ),
      );
    }
  });
}
