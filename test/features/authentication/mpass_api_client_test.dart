import 'dart:async';
import 'dart:convert';

import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/features/authentication/data/mpass_api_client.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test('parsea un login correcto', () async {
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
    final client = MpassApiClient(transport: transport);

    final session = await client.login(
      email: 'fake@example.com',
      password: 'fake-password',
      passKey: 'fake-pass-key',
      xClientId: 'fake-client-id',
      deviceId: '0123456789abcdef',
    );

    expect(session.accessToken, 'fake-access-token');
    expect(session.idUser, 'fake-user-id');
    expect(session.tokenSecExpiration, 2592000);
    expect(transport.requests.single.headers, isNot(contains('latitude')));
  });

  test('rechaza login con code incorrecto', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({'code': '99', 'description': 'fake'}),
      ]),
    );

    expect(
      () => client.login(
        email: 'fake@example.com',
        password: 'fake-password',
        passKey: 'fake-pass-key',
        xClientId: 'fake-client-id',
        deviceId: '0123456789abcdef',
      ),
      throwsA(isA<AuthenticationException>()),
    );
  });

  test('rechaza login sin data', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({'code': '00', 'data': []}),
      ]),
    );

    expect(
      () => client.login(
        email: 'fake@example.com',
        password: 'fake-password',
        passKey: 'fake-pass-key',
        xClientId: 'fake-client-id',
        deviceId: '0123456789abcdef',
      ),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });

  test('acepta userdata con code 01 y DS_DN', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({
          'code': '01',
          'description': 'El usuario tiene contratos',
          'data': {'DS_DN': 'fake-ds-dn', 'DS_NIF': 'ignored'},
        }),
      ]),
    );

    final dsDn = await client.fetchDsDn(
      session: _session(),
      email: 'fake@example.com',
      deviceId: '0123456789abcdef',
    );

    expect(dsDn, 'fake-ds-dn');
  });

  test('acepta userdata con code 00 y DS_DN', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({
          'code': '00',
          'data': {'DS_DN': 'fake-ds-dn'},
        }),
      ]),
    );

    final dsDn = await client.fetchDsDn(
      session: _session(),
      email: 'fake@example.com',
      deviceId: '0123456789abcdef',
    );

    expect(dsDn, 'fake-ds-dn');
  });

  test('rechaza userdata sin DS_DN', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({
          'code': '01',
          'data': {'DS_NIF': 'ignored'},
        }),
      ]),
    );

    expect(
      () => client.fetchDsDn(
        session: _session(),
        email: 'fake@example.com',
        deviceId: '0123456789abcdef',
      ),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });

  test('normaliza viajes y descarta campos sensibles', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({
          'code': '00',
          'data': [
            {
              'trip_id': 'trip-1',
              'userId': 'ignored',
              'payment': {'amount': 1},
              'locator': 'ignored',
              'id_bike': '00001234',
              'trip_cost': '1.2300',
              'undock': {
                'undock_station_number': '90',
                'undock_station_name': 'Manuel Becerra',
                'undock_ts': '2026-08-01T09:00:00',
              },
              'dock': {
                'dock_station_number': '91',
                'dock_station_name': '',
                'dock_ts': '2026-08-01T09:06:00',
              },
              'trip_minutes': 6.0,
              'trip_interval': '00:06:00',
            },
          ],
        }),
      ]),
    );

    final trips = await client.fetchTrips(
      session: _session(),
      email: 'fake@example.com',
      nif: 'fake-ds-dn',
      deviceId: '0123456789abcdef',
    );

    expect(trips.single.externalId, 'trip-1');
    expect(trips.single.originStationName, 'Manuel Becerra');
    expect(trips.single.destinationStationName, isNull);
    expect(trips.single.bikeId, '1234');
    expect(trips.single.tripCost, '1.2300');
    expect(jsonEncode(trips.single.toString()), isNot(contains('payment')));
    expect(jsonEncode(trips.single.toString()), isNot(contains('userId')));
  });

  test('solo anade la cabecera page a partir de la segunda pagina', () async {
    final transport = QueuedHttpTransport([
      _jsonResponse({'code': '00', 'data': []}),
      _jsonResponse({'code': '00', 'data': []}),
    ]);
    final client = MpassApiClient(transport: transport);

    await client.fetchTrips(
      session: _session(),
      email: 'fake@example.com',
      nif: 'fake-ds-dn',
      deviceId: '0123456789abcdef',
    );
    await client.fetchTrips(
      session: _session(),
      email: 'fake@example.com',
      nif: 'fake-ds-dn',
      deviceId: '0123456789abcdef',
      page: 1,
    );

    expect(transport.requests.first.headers, isNot(contains('page')));
    expect(transport.requests.last.headers['page'], '1');
  });

  test('no imprime secretos en errores', () async {
    final client = MpassApiClient(
      transport: QueuedHttpTransport([
        _jsonResponse({'code': '99'}),
      ]),
    );
    final printed = <String>[];

    await runZoned(
      () async {
        try {
          await client.login(
            email: 'secret@example.com',
            password: 'secret-password',
            passKey: 'secret-pass-key',
            xClientId: 'secret-client-id',
            deviceId: '0123456789abcdef',
          );
        } on Object {
          // Expected.
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    final output = printed.join('\n');
    expect(output, isNot(contains('secret@example.com')));
    expect(output, isNot(contains('secret-password')));
    expect(output, isNot(contains('secret-pass-key')));
    expect(output, isNot(contains('secret-client-id')));
  });
}

HttpResponseData _jsonResponse(Map<String, Object?> body, {int status = 200}) {
  return HttpResponseData(
    statusCode: status,
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json'},
  );
}

MpassSession _session() {
  return MpassSession(
    accessToken: 'fake-access-token',
    idUser: 'fake-user-id',
    tokenSecExpiration: 2592000,
    obtainedAt: DateTime(2026, 8, 2),
  );
}
