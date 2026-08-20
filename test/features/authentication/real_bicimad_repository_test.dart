import 'dart:convert';

import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/core/config/bicimad_build_config.dart';
import 'package:bicimad_social/features/authentication/data/bicimad_secure_storage.dart';
import 'package:bicimad_social/features/authentication/data/mpass_api_client.dart';
import 'package:bicimad_social/features/authentication/data/real_bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/data/technical_config_resolver.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test('no realiza peticiones si falta configuracion tecnica', () async {
    final store = InMemorySecureKeyValueStore();
    final transport = QueuedHttpTransport();
    final repository = _repository(store: store, transport: transport);

    expect(
      () => repository.login(email: 'fake@example.com', password: 'fake'),
      throwsA(isA<ConfigurationException>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('mantiene el flujo login userdata trips con HTTP simulado', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    await storage.saveTechnicalConfig(
      passKey: 'fake-pass-key',
      xClientId: 'fake-client-id',
    );
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
      _jsonResponse({
        'code': '01',
        'data': {'DS_DN': 'fake-ds-dn', 'DS_NIF': 'ignored'},
      }),
      _jsonResponse({
        'code': '00',
        'data': [
          {
            'trip_id': 'trip-1',
            'userId': 'ignored',
            'payment': 'ignored',
            'locator': 'ignored',
            'contractCode': 'ignored',
            'undock': {
              'undock_station_number': '90',
              'undock_station_name': 'Manuel Becerra',
              'undock_ts': '2026-08-01T09:00:00',
            },
            'dock': {
              'dock_station_number': '91',
              'dock_station_name': 'Felipe II',
              'dock_ts': '2026-08-01T09:06:00',
            },
            'trip_minutes': 6.0,
            'trip_interval': '00:06:00',
          },
        ],
      }),
    ]);
    final repository = _repository(store: store, transport: transport);

    final session = await repository.login(
      email: 'fake@example.com',
      password: 'fake-password',
    );
    final trips = await repository.fetchTrips(session);

    expect(trips.single.externalId, 'trip-1');
    expect(trips.single.originStationName, 'Manuel Becerra');
    expect(trips.single.destinationStationName, 'Felipe II');
    expect(trips.single.durationSeconds, 360);
    expect(store.values.values, isNot(contains('fake-password')));
    expect(store.values.values, isNot(contains('fake-ds-dn')));
    expect(transport.requests, hasLength(3));
    expect(transport.requests.first.body.toString(), contains('fake-pass-key'));
    expect(
      transport.requests.first.body.toString(),
      contains('fake-client-id'),
    );

    final deviceIds = {
      for (final request in transport.requests) request.headers['deviceId'],
    };
    expect(deviceIds.length, 1);
    expect(deviceIds.single, matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('la configuracion completa de build tiene prioridad', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    await storage.saveTechnicalConfig(
      passKey: 'stored-pass-key',
      xClientId: 'stored-client-id',
    );
    store.readKeys.clear();
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
        passKey: 'build-pass-key',
        xClientId: 'build-client-id',
      ),
    );

    await repository.login(
      email: 'fake@example.com',
      password: 'fake-password',
    );

    expect(
      transport.requests.single.body.toString(),
      contains('build-pass-key'),
    );
    expect(
      transport.requests.single.body.toString(),
      contains('build-client-id'),
    );
    expect(
      transport.requests.single.body.toString(),
      isNot(contains('stored-pass-key')),
    );
    expect(
      transport.requests.single.body.toString(),
      isNot(contains('stored-client-id')),
    );
    expect(store.readKeys, isNot(contains(BicimadSecureStorage.passKeyKey)));
    expect(store.readKeys, isNot(contains(BicimadSecureStorage.xClientIdKey)));
  });

  test('restaura sesion valida y elimina sesion caducada', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    await storage.saveSession(
      session: MpassSession(
        accessToken: 'fake-access-token',
        idUser: 'fake-user-id',
        tokenSecExpiration: 60,
        obtainedAt: DateTime.now(),
      ),
      email: 'fake@example.com',
    );
    final repository = _repository(
      store: store,
      transport: QueuedHttpTransport(),
    );

    expect((await repository.restoreSession())?.idUser, 'fake-user-id');

    await storage.saveSession(
      session: MpassSession(
        accessToken: 'old-token',
        idUser: 'fake-user-id',
        tokenSecExpiration: 1,
        obtainedAt: DateTime(2020),
      ),
      email: 'fake@example.com',
    );

    expect(repository.restoreSession, throwsA(isA<SessionExpiredException>()));
  });

  test('clearSession no elimina configuracion tecnica ni deviceId', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    await storage.saveTechnicalConfig(
      passKey: 'fake-pass-key',
      xClientId: 'fake-client-id',
    );
    final deviceId = await storage.getOrCreateDeviceId();
    await storage.saveSession(
      session: MpassSession(
        accessToken: 'fake-access-token',
        idUser: 'fake-user-id',
        tokenSecExpiration: 60,
        obtainedAt: DateTime.now(),
      ),
      email: 'fake@example.com',
    );
    final repository = _repository(
      store: store,
      transport: QueuedHttpTransport(),
    );

    await repository.clearSession();

    expect(await storage.readTechnicalConfig(), isNotNull);
    expect(await storage.getOrCreateDeviceId(), deviceId);
    expect(await storage.readSession(), isNull);
  });

  test('reutiliza userdata durante todas las paginas de un sync', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    final session = MpassSession(
      accessToken: 'fake-access-token',
      idUser: 'fake-user-id',
      tokenSecExpiration: 3600,
      obtainedAt: DateTime.now(),
    );
    await storage.saveSession(session: session, email: 'fake@example.com');
    final transport = QueuedHttpTransport([
      _jsonResponse({
        'code': '01',
        'data': {'DS_DN': 'fake-ds-dn'},
      }),
      _jsonResponse({'code': '00', 'data': []}),
      _jsonResponse({'code': '00', 'data': []}),
    ]);
    final repository = _repository(store: store, transport: transport);

    await repository.fetchTrips(session);
    await repository.fetchTrips(session, page: 1);

    expect(transport.requests, hasLength(3));
    expect(transport.requests[1].headers, isNot(contains('page')));
    expect(transport.requests[2].headers['page'], '1');
  });
}

RealBicimadRepository _repository({
  required InMemorySecureKeyValueStore store,
  required QueuedHttpTransport transport,
  BicimadBuildConfig buildConfig = const BicimadBuildConfig(
    passKey: '',
    xClientId: '',
  ),
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
