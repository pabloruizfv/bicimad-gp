import 'dart:io';
import 'dart:typed_data';

import 'package:bicimad_social/core/diagnostics/bicimad_diagnostics.dart';
import 'package:bicimad_social/core/network/tls_certificate_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(BicimadDiagnostics.resetOutput);

  test('extrae CN cuando aparece al principio', () {
    expect(
      extractCommonName('CN=api.example.test, O=Example Service, C=ES'),
      'api.example.test',
    );
  });

  test('extrae CN cuando aparece en otra posicion', () {
    expect(
      extractCommonName('O=Example,CN=Example Test Root CA,C=ES'),
      'Example Test Root CA',
    );
  });

  test('tolera espacios y clave sin distinguir mayusculas', () {
    expect(
      extractCommonName(' O = Example , cN = Example Root , C = ES '),
      'Example Root',
    );
  });

  test('devuelve unknown si no existe CN o esta vacio', () {
    expect(extractCommonName('O=Example, C=ES'), 'unknown');
    expect(extractCommonName('O=Example, CN= , C=ES'), 'unknown');
  });

  test('calcula selfSigned y validNow', () {
    final now = DateTime(2026, 8, 2, 12);
    final diagnostics = TlsCertificateDiagnostics(now: () => now);
    final metadata = TlsCertificateMetadata(
      subject: 'CN=Example Test Root CA, O=Example CA, C=ES',
      issuer: 'CN=Example Test Root CA, O=Example CA, C=ES',
      startValidity: DateTime(2026, 8, 2, 11),
      endValidity: DateTime(2026, 8, 2, 13),
    );

    final line = diagnostics.buildLine(metadata);

    expect(line.subjectCn, 'Example Test Root CA');
    expect(line.issuerCn, 'Example Test Root CA');
    expect(line.selfSigned, isTrue);
    expect(line.validNow, isTrue);
  });

  test('selfSigned=false cuando subject e issuer son distintos', () {
    final diagnostics = TlsCertificateDiagnostics(
      now: () => DateTime(2026, 8, 2, 12),
    );

    final line = diagnostics.buildLine(
      TlsCertificateMetadata(
        subject: 'CN=api.example.test, O=Example Service, C=ES',
        issuer: 'CN=Example Test Root CA, O=Example CA, C=ES',
        startValidity: DateTime(2026, 8, 2, 11),
        endValidity: DateTime(2026, 8, 2, 13),
      ),
    );

    expect(line.selfSigned, isFalse);
  });

  test('validNow=true exactamente en los limites', () {
    final start = DateTime(2026, 8, 2, 11);
    final end = DateTime(2026, 8, 2, 13);

    expect(
      TlsCertificateDiagnostics(
        now: () => start,
      ).buildLine(_metadata(startValidity: start, endValidity: end)).validNow,
      isTrue,
    );
    expect(
      TlsCertificateDiagnostics(
        now: () => end,
      ).buildLine(_metadata(startValidity: start, endValidity: end)).validNow,
      isTrue,
    );
  });

  test('validNow=false antes y despues del intervalo', () {
    final start = DateTime(2026, 8, 2, 11);
    final end = DateTime(2026, 8, 2, 13);

    expect(
      TlsCertificateDiagnostics(
        now: () => start.subtract(const Duration(seconds: 1)),
      ).buildLine(_metadata(startValidity: start, endValidity: end)).validNow,
      isFalse,
    );
    expect(
      TlsCertificateDiagnostics(
        now: () => end.add(const Duration(seconds: 1)),
      ).buildLine(_metadata(startValidity: start, endValidity: end)).validNow,
      isFalse,
    );
  });

  test('la linea diagnostica solo contiene campos seguros', () {
    final lines = <String>[];
    BicimadDiagnostics.output = (message, {wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };
    final subject = 'CN=api.example.test, O=Example Service, C=ES';
    final issuer = 'CN=Example Test Root CA, O=Example CA, C=ES';

    TlsCertificateDiagnostics(now: () => DateTime(2026, 8, 2, 12)).logUntrusted(
      TlsCertificateMetadata(
        subject: subject,
        issuer: issuer,
        startValidity: DateTime(2026, 8, 2, 11),
        endValidity: DateTime(2026, 8, 2, 13),
      ),
    );

    final line = lines.single;
    expect(
      line,
      '[BICIMAD_DIAG] stage=tls_certificate event=untrusted '
      'subjectCn=api.example.test issuerCn=Example Test Root CA '
      'selfSigned=false validNow=true',
    );
    expect(line, isNot(contains(subject)));
    expect(line, isNot(contains(issuer)));
    expect(line, isNot(contains('PEM')));
    expect(line, isNot(contains('DER')));
    expect(line, isNot(contains('serial')));
    expect(line, isNot(contains('fingerprint')));
    expect(line, isNot(contains('secret-pass-key')));
    expect(line, isNot(contains('secret-client-id')));
    expect(line, isNot(contains('secret-token')));
  });

  test('callback devuelve false para apiemtpay y deduplica el diagnostico', () {
    final lines = <String>[];
    BicimadDiagnostics.output = (message, {wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };
    final diagnostics = TlsCertificateDiagnostics(
      now: () => DateTime(2026, 8, 2, 12),
    );
    final certificate = _FakeX509Certificate(
      subject: 'CN=api.example.test, O=Example Service, C=ES',
      issuer: 'CN=Example Test Root CA, O=Example CA, C=ES',
      startValidity: DateTime(2026, 8, 2, 11),
      endValidity: DateTime(2026, 8, 2, 13),
    );

    expect(
      diagnostics.rejectWithOptionalDiagnostic(
        certificate,
        TlsCertificateDiagnostics.diagnosticHost,
        443,
      ),
      isFalse,
    );
    expect(
      diagnostics.rejectWithOptionalDiagnostic(
        certificate,
        TlsCertificateDiagnostics.diagnosticHost,
        443,
      ),
      isFalse,
    );

    expect(lines, hasLength(1));
  });

  test('callback devuelve false y no registra otros hosts', () {
    final lines = <String>[];
    BicimadDiagnostics.output = (message, {wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };

    final result = TlsCertificateDiagnostics().rejectWithOptionalDiagnostic(
      _FakeX509Certificate(),
      'other.example.test',
      443,
    );

    expect(result, isFalse);
    expect(lines, isEmpty);
  });
}

TlsCertificateMetadata _metadata({
  required DateTime startValidity,
  required DateTime endValidity,
}) {
  return TlsCertificateMetadata(
    subject: 'CN=api.example.test, O=Example Service, C=ES',
    issuer: 'CN=Example Test Root CA, O=Example CA, C=ES',
    startValidity: startValidity,
    endValidity: endValidity,
  );
}

class _FakeX509Certificate implements X509Certificate {
  _FakeX509Certificate({
    this.subject = 'CN=api.example.test, O=Example Service, C=ES',
    this.issuer = 'CN=Example Test Root CA, O=Example CA, C=ES',
    DateTime? startValidity,
    DateTime? endValidity,
  }) : startValidity = startValidity ?? DateTime(2026, 8, 2, 11),
       endValidity = endValidity ?? DateTime(2026, 8, 2, 13);

  @override
  final String subject;

  @override
  final String issuer;

  @override
  final DateTime startValidity;

  @override
  final DateTime endValidity;

  @override
  Uint8List get der => Uint8List(0);

  @override
  String get pem => '';

  @override
  Uint8List get sha1 => Uint8List(0);
}
