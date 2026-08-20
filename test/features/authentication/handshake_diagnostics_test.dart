import 'dart:io';

import 'package:bicimad_social/core/diagnostics/bicimad_diagnostics.dart';
import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/features/authentication/data/mpass_api_client.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(BicimadDiagnostics.resetOutput);

  for (final scenario in <_HandshakeScenario>[
    _HandshakeScenario(
      message: 'CERTIFICATE_VERIFY_FAILED',
      reason: 'certificate_verify_failed',
    ),
    _HandshakeScenario(
      message: 'unable to get local issuer certificate',
      reason: 'unable_to_get_issuer',
    ),
    _HandshakeScenario(
      message: 'self signed certificate',
      reason: 'self_signed_certificate',
    ),
    _HandshakeScenario(
      message: 'hostname mismatch',
      reason: 'hostname_mismatch',
    ),
    _HandshakeScenario(
      message: 'certificate has expired',
      reason: 'certificate_expired',
    ),
    _HandshakeScenario(
      message: 'tlsv1 alert protocol version',
      reason: 'protocol_version',
    ),
    _HandshakeScenario(
      message: 'sslv3 alert handshake failure',
      reason: 'handshake_failure',
    ),
    _HandshakeScenario(
      message: 'connection closed during handshake',
      reason: 'connection_closed_during_handshake',
    ),
    _HandshakeScenario(message: 'unrecognized tls problem', reason: 'other'),
  ]) {
    test('clasifica HandshakeException como ${scenario.reason}', () async {
      final lines = <String>[];
      BicimadDiagnostics.output = (message, {wrapWidth}) {
        if (message != null) {
          lines.add(message);
        }
      };
      final client = MpassApiClient(
        transport: _ThrowingHandshakeTransport(
          HandshakeException(
            scenario.message,
            OSError('os ${scenario.message}', 123),
          ),
        ),
      );

      await expectLater(
        client.fetchDsDn(
          session: _session(),
          email: 'secret@example.com',
          deviceId: 'secret-device-id',
        ),
        throwsA(isA<NetworkException>()),
      );

      expect(
        lines,
        contains(
          '[BICIMAD_DIAG] stage=userdata event=request_started '
          'host=apiemtpay.emtmadrid.es path=/v2/bicimad/userdata/ method=GET',
        ),
      );
      expect(
        lines,
        contains(
          '[BICIMAD_DIAG] stage=userdata event=error '
          'type=HandshakeException reason=${scenario.reason} osCode=123',
        ),
      );

      final output = lines.join('\n');
      expect(output, isNot(contains(scenario.message)));
      expect(output, isNot(contains('os ${scenario.message}')));
      expect(output, isNot(contains('secret@example.com')));
      expect(output, isNot(contains('secret-device-id')));
      expect(output, isNot(contains('secret-access-token')));
      expect(output, isNot(contains('secret-user-id')));
    });
  }

  test(
    'registra osCode none cuando HandshakeException no incluye OSError',
    () async {
      final lines = <String>[];
      BicimadDiagnostics.output = (message, {wrapWidth}) {
        if (message != null) {
          lines.add(message);
        }
      };
      final client = MpassApiClient(
        transport: _ThrowingHandshakeTransport(
          const HandshakeException('handshake failure'),
        ),
      );

      await expectLater(
        client.fetchDsDn(
          session: _session(),
          email: 'secret@example.com',
          deviceId: 'secret-device-id',
        ),
        throwsA(isA<NetworkException>()),
      );

      expect(
        lines,
        contains(
          '[BICIMAD_DIAG] stage=userdata event=error '
          'type=HandshakeException reason=handshake_failure osCode=none',
        ),
      );
    },
  );
}

class _HandshakeScenario {
  const _HandshakeScenario({required this.message, required this.reason});

  final String message;
  final String reason;
}

class _ThrowingHandshakeTransport implements HttpTransport {
  const _ThrowingHandshakeTransport(this.error);

  final HandshakeException error;

  @override
  Future<HttpResponseData> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    throw error;
  }

  @override
  Future<HttpResponseData> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    throw error;
  }

  @override
  void close() {}
}

MpassSession _session() {
  return MpassSession(
    accessToken: 'secret-access-token',
    idUser: 'secret-user-id',
    tokenSecExpiration: 2592000,
    obtainedAt: DateTime(2026, 8, 2),
  );
}
