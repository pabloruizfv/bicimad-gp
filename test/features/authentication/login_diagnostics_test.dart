import 'dart:convert';

import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/core/config/bicimad_build_config.dart';
import 'package:bicimad_social/core/diagnostics/bicimad_diagnostics.dart';
import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/core/storage/secure_key_value_store.dart';
import 'package:bicimad_social/features/authentication/data/bicimad_secure_storage.dart';
import 'package:bicimad_social/features/authentication/data/mpass_api_client.dart';
import 'package:bicimad_social/features/authentication/data/real_bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/data/technical_config_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  tearDown(BicimadDiagnostics.resetOutput);

  test(
    'continua desde config build resuelta hasta deviceId y login request',
    () async {
      final lines = <String>[];
      BicimadDiagnostics.output = (message, {wrapWidth}) {
        if (message != null) {
          lines.add(message);
        }
      };
      final store = InMemorySecureKeyValueStore();
      final transport = QueuedHttpTransport([
        _jsonResponse({
          'code': '00',
          'data': [
            {
              'accessToken': 'fake-access-token',
              'idUser': 'fake-user-id',
              'tokenSecExpiration': 2592000,
            },
          ],
        }),
      ]);
      final repository = _repository(
        store: store,
        transport: transport,
        buildConfig: const BicimadBuildConfig(
          passKey: 'fake-build-pass-key',
          xClientId: 'fake-build-client-id',
        ),
      );

      await repository.login(
        email: 'fake@example.com',
        password: 'fake-password',
      );

      expect(
        lines,
        containsAllInOrder([
          '[BICIMAD_DIAG] stage=config event=resolve_started',
          '[BICIMAD_DIAG] stage=config event=resolved source=build configured=true',
          '[BICIMAD_DIAG] stage=device_id event=read_started',
          '[BICIMAD_DIAG] stage=device_id event=read_completed existing=false',
          '[BICIMAD_DIAG] stage=device_id event=create_started',
          '[BICIMAD_DIAG] stage=device_id event=create_completed',
          '[BICIMAD_DIAG] stage=login event=call_started',
          '[BICIMAD_DIAG] stage=login event=request_started host=api.mpass.mobi path=/v1/core/identity/login/integrator method=POST',
          '[BICIMAD_DIAG] stage=login event=response status=200 apiCode=00',
        ]),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'PlatformException de secure storage se clasifica como almacenamiento',
    () async {
      final lines = <String>[];
      BicimadDiagnostics.output = (message, {wrapWidth}) {
        if (message != null) {
          lines.add(message);
        }
      };
      final transport = QueuedHttpTransport();
      final repository = _repository(
        store: _ThrowingSecureKeyValueStore(),
        transport: transport,
        buildConfig: const BicimadBuildConfig(
          passKey: 'fake-build-pass-key',
          xClientId: 'fake-build-client-id',
        ),
      );

      await expectLater(
        repository.login(email: 'fake@example.com', password: 'fake'),
        throwsA(isA<SecureStorageException>()),
      );
      expect(
        lines,
        contains(
          '[BICIMAD_DIAG] stage=device_id event=error type=PlatformException',
        ),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test('la composicion normal usa repositorio real y no mock', () {
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(
          InMemorySecureKeyValueStore(),
        ),
        httpTransportProvider.overrideWithValue(QueuedHttpTransport()),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(bicimadRepositoryProvider),
      isA<RealBicimadRepository>(),
    );
  });

  test('ninguna linea de diagnostico contiene secretos ficticios', () async {
    final lines = <String>[];
    BicimadDiagnostics.output = (message, {wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };
    final repository = _repository(
      store: InMemorySecureKeyValueStore(),
      transport: QueuedHttpTransport([
        _jsonResponse({
          'code': '00',
          'data': [
            {
              'accessToken': 'fake-access-token',
              'idUser': 'fake-user-id',
              'tokenSecExpiration': 2592000,
            },
          ],
        }),
      ]),
      buildConfig: const BicimadBuildConfig(
        passKey: 'secret-pass-key',
        xClientId: 'secret-client-id',
      ),
    );

    await repository.login(
      email: 'secret@example.com',
      password: 'secret-password',
    );

    final output = lines.join('\n');
    expect(output, isNot(contains('secret-pass-key')));
    expect(output, isNot(contains('secret-client-id')));
    expect(output, isNot(contains('secret@example.com')));
    expect(output, isNot(contains('secret-password')));
    expect(output, isNot(contains('fake-access-token')));
    expect(output, isNot(contains('fake-user-id')));
  });
}

RealBicimadRepository _repository({
  required SecureKeyValueStore store,
  required QueuedHttpTransport transport,
  required BicimadBuildConfig buildConfig,
}) {
  final secureStorage = BicimadSecureStorage(store: store);
  return RealBicimadRepository(
    apiClient: MpassApiClient(transport: transport),
    secureStorage: secureStorage,
    technicalConfigResolver: TechnicalConfigResolver(
      buildConfig: buildConfig,
      secureStorage: secureStorage,
    ),
  );
}

HttpResponseData _jsonResponse(Map<String, Object?> body, {int status = 200}) {
  return HttpResponseData(
    statusCode: status,
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json'},
  );
}

class _ThrowingSecureKeyValueStore implements SecureKeyValueStore {
  @override
  Future<void> delete(String key) async {
    throw PlatformException(code: 'fake');
  }

  @override
  Future<String?> read(String key) async {
    throw PlatformException(code: 'fake');
  }

  @override
  Future<void> write({required String key, required String value}) async {
    throw PlatformException(code: 'fake');
  }
}
