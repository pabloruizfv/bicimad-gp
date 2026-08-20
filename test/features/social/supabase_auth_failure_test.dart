import 'dart:io';

import 'package:bicimad_social/features/social/data/supabase_social_repository.dart';
import 'package:bicimad_social/features/social/domain/social_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('cada sendOtp realiza una sola llamada a signInWithOtp', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://project.example.test',
      'fake-publishable-key',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseSocialRepository(client);

    await repository.sendOtp('new.user@example.test');

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/auth/v1/otp');
  });

  test('clasifica correo rechazado por el proveedor SMTP', () {
    const error = AuthApiException(
      'private server message',
      statusCode: '422',
      code: 'email_address_not_authorized',
    );

    expect(
      classifySupabaseAuthFailure(error),
      SocialAuthFailureKind.emailNotAuthorized,
    );
  });

  test('clasifica limites, OTP desactivado y alta desactivada', () {
    expect(
      classifySupabaseAuthFailure(
        const AuthApiException(
          'private',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      ),
      SocialAuthFailureKind.rateLimited,
    );
    expect(
      classifySupabaseAuthFailure(
        const AuthApiException('private', code: 'otp_disabled'),
      ),
      SocialAuthFailureKind.otpDisabled,
    );
    expect(
      classifySupabaseAuthFailure(
        const AuthApiException('private', code: 'signup_disabled'),
      ),
      SocialAuthFailureKind.signupDisabled,
    );
  });

  test('clasifica fallo TLS sin exponer el mensaje original', () {
    final error = AuthUnknownException(
      message: 'private wrapper message',
      originalError: const HandshakeException('private TLS message'),
    );

    expect(
      classifySupabaseAuthFailure(error),
      SocialAuthFailureKind.secureConnection,
    );
    final diagnostic = buildSafeSupabaseAuthDiagnostic('send_otp', error);
    expect(diagnostic, contains('type=AuthUnknownException'));
    expect(diagnostic, isNot(contains('private')));
    expect(diagnostic, isNot(contains('TLS message')));
  });

  test('diagnostico solo conserva estado y codigo con formato seguro', () {
    const error = AuthApiException(
      'email and response must stay private',
      statusCode: '429',
      code: 'over_request_rate_limit',
    );

    final diagnostic = buildSafeSupabaseAuthDiagnostic('send_otp', error);

    expect(
      diagnostic,
      '[SOCIAL_DIAG] stage=auth event=error operation=send_otp '
      'type=AuthApiException status=429 code=over_request_rate_limit',
    );
    expect(diagnostic, isNot(contains(error.message)));
  });
}
