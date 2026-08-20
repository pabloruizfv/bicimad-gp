import 'dart:io';

import '../diagnostics/bicimad_diagnostics.dart';

class TlsCertificateMetadata {
  const TlsCertificateMetadata({
    required this.subject,
    required this.issuer,
    required this.startValidity,
    required this.endValidity,
  });

  final String subject;
  final String issuer;
  final DateTime startValidity;
  final DateTime endValidity;
}

class TlsCertificateDiagnosticLine {
  const TlsCertificateDiagnosticLine({
    required this.subjectCn,
    required this.issuerCn,
    required this.selfSigned,
    required this.validNow,
  });

  final String subjectCn;
  final String issuerCn;
  final bool selfSigned;
  final bool validNow;

  Map<String, Object> toFields() {
    return {
      'subjectCn': subjectCn,
      'issuerCn': issuerCn,
      'selfSigned': selfSigned,
      'validNow': validNow,
    };
  }
}

class TlsCertificateDiagnostics {
  TlsCertificateDiagnostics({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const diagnosticHost = 'apiemtpay.emtmadrid.es';

  final DateTime Function() _now;
  final Set<String> _reportedHosts = {};

  bool rejectWithOptionalDiagnostic(
    X509Certificate certificate,
    String host,
    int port,
  ) {
    if (host == diagnosticHost && _reportedHosts.add(host)) {
      logUntrusted(
        TlsCertificateMetadata(
          subject: certificate.subject,
          issuer: certificate.issuer,
          startValidity: certificate.startValidity,
          endValidity: certificate.endValidity,
        ),
      );
    }
    return false;
  }

  void logUntrusted(TlsCertificateMetadata metadata) {
    final line = buildLine(metadata);
    BicimadDiagnostics.log('tls_certificate', 'untrusted', line.toFields());
  }

  TlsCertificateDiagnosticLine buildLine(TlsCertificateMetadata metadata) {
    final now = _now();
    return TlsCertificateDiagnosticLine(
      subjectCn: extractCommonName(metadata.subject),
      issuerCn: extractCommonName(metadata.issuer),
      selfSigned: metadata.subject == metadata.issuer,
      validNow:
          !now.isBefore(metadata.startValidity) &&
          !now.isAfter(metadata.endValidity),
    );
  }
}

String extractCommonName(String distinguishedName) {
  for (final part in distinguishedName.split(',')) {
    final separator = part.indexOf('=');
    if (separator < 0) {
      continue;
    }
    final key = part.substring(0, separator).trim();
    if (key.toLowerCase() != 'cn') {
      continue;
    }
    final value = part.substring(separator + 1).trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return 'unknown';
}
