import 'dart:async';
import 'dart:convert';

import 'package:bicimad_social/core/diagnostics/bicimad_diagnostics.dart';
import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  tearDown(BicimadDiagnostics.resetOutput);

  test('Android selecciona la factoria Cronet', () {
    final lines = <String>[];
    BicimadDiagnostics.output = (message, {wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };
    final cronetClient = _RecordingClient();
    final ioClient = _RecordingClient();

    final selected = createPlatformHttpClient(
      isAndroid: true,
      cronetClientFactory: () => cronetClient,
      ioClientFactory: () => ioClient,
    );

    expect(selected, same(cronetClient));
    expect(
      lines,
      contains(
        '[BICIMAD_DIAG] stage=http_transport event=created implementation=cronet',
      ),
    );
    expect(ioClient.sendCount, 0);
  });

  test('una plataforma no Android selecciona IOClient', () {
    final lines = <String>[];
    BicimadDiagnostics.output = (message, {wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };
    final cronetClient = _RecordingClient();
    final ioClient = _RecordingClient();

    final selected = createPlatformHttpClient(
      isAndroid: false,
      cronetClientFactory: () => cronetClient,
      ioClientFactory: () => ioClient,
    );

    expect(selected, same(ioClient));
    expect(
      lines,
      contains(
        '[BICIMAD_DIAG] stage=http_transport event=created implementation=io_client',
      ),
    );
    expect(cronetClient.sendCount, 0);
  });

  test('PackageHttpTransport usa el cliente inyectado y lo cierra', () async {
    final client = _RecordingClient();
    final transport = PackageHttpTransport(client: client);

    await transport.get(
      Uri.parse('https://example.test/userdata'),
      headers: const {'x-test': '1'},
    );
    await transport.post(
      Uri.parse('https://example.test/login'),
      headers: const {'content-type': 'application/json'},
      body: '{"ok":true}',
    );
    transport.close();

    expect(client.requests, hasLength(2));
    expect(client.requests[0].method, 'GET');
    expect(client.requests[1].method, 'POST');
    expect(client.isClosed, isTrue);
  });

  test(
    'la factoria real IOClient no configura SecurityContext personalizado',
    () {
      final client = createIoHttpClient();
      addTearDown(client.close);

      expect(client, isA<http.Client>());
    },
  );
}

class _RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  var sendCount = 0;
  var isClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    sendCount++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"code":"00","data":[]}')),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    isClosed = true;
    super.close();
  }
}
