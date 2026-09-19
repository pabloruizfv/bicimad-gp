import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/diagnostics/bicimad_diagnostics.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/http_transport.dart';
import '../../../core/utils/bike_id.dart';
import '../../../core/utils/decimal_amount.dart';
import '../../trips/domain/bicimad_trip.dart';
import '../domain/mpass_session.dart';

class MpassApiClient {
  const MpassApiClient({required this.transport});

  static final Uri _loginUri = Uri.parse(
    'https://api.mpass.mobi/v1/core/identity/login/integrator',
  );
  static final Uri _userdataUri = Uri.parse(
    'https://apiemtpay.emtmadrid.es/v2/bicimad/userdata/',
  );
  static final Uri _tripsUri = Uri.parse(
    'https://apiemtpay.emtmadrid.es/v2/bicimad/trips/',
  );

  static const _appName = 'bicimad';
  static const _appPlatform = 'Android';
  static const _appPlatformVersion = 'Android TIRAMISU';
  static const _appVersion = '5.8.8';
  static const _loginLanguage = 'ES';
  static const _apiLanguage = 'es';
  static const _deviceModel =
      '{"name":"Android device","model":"Android","version":"13"}';

  final HttpTransport transport;

  Future<MpassSession> login({
    required String email,
    required String password,
    required String passKey,
    required String xClientId,
    required String deviceId,
  }) async {
    final response = await _guardNetwork('login', () {
      BicimadDiagnostics.log('login', 'request_started', {
        'host': _loginUri.host,
        'path': _loginUri.path,
        'method': 'POST',
      });
      return transport.post(
        _loginUri,
        headers: {
          'appName': _appName,
          'appPlatform': _appPlatform,
          'appPlatformVersion': _appPlatformVersion,
          'appVersion': _appVersion,
          'debug': '1',
          'deviceId': deviceId,
          'deviceModel': _deviceModel,
          'language': _loginLanguage,
          'X-ClientId': xClientId,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'passKey': passKey,
          'password': password,
          'X-ClientId': xClientId,
        }),
      );
    });
    BicimadDiagnostics.log('login', 'response', {
      'status': response.statusCode,
      'apiCode': _apiCode(response),
    });

    final body = _decodeMap(response);
    if (body['code']?.toString() != '00') {
      throw const AuthenticationException(
        'No se ha podido iniciar sesión con MPass.',
      );
    }

    final data = body['data'];
    if (data is! List || data.isEmpty || data.first is! Map) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada del login MPass.',
      );
    }

    final first = Map<String, Object?>.from(data.first as Map);
    final accessToken = first['accessToken']?.toString() ?? '';
    final idUser = first['idUser']?.toString() ?? '';
    final expiration = int.tryParse(
      first['tokenSecExpiration']?.toString() ?? '',
    );
    if (accessToken.isEmpty || idUser.isEmpty || expiration == null) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada del login MPass.',
      );
    }

    return MpassSession(
      accessToken: accessToken,
      idUser: idUser,
      tokenSecExpiration: expiration,
      obtainedAt: DateTime.now(),
    );
  }

  Future<String> fetchDsDn({
    required MpassSession session,
    required String email,
    required String deviceId,
  }) async {
    final response = await _guardNetwork('userdata', () {
      BicimadDiagnostics.log('userdata', 'request_started', {
        'host': _userdataUri.host,
        'path': _userdataUri.path,
        'method': 'GET',
      });
      return transport.get(
        _userdataUri,
        headers: _authenticatedHeaders(
          accessToken: session.accessToken,
          email: email,
          userId: session.idUser,
          deviceId: deviceId,
        ),
      );
    });
    final body = _decodeMap(response);
    final code = body['code']?.toString();
    if (code != '00' && code != '01') {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al consultar datos de usuario.',
      );
    }

    final data = body['data'];
    if (data is! Map) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al consultar datos de usuario.',
      );
    }

    final dsDn = data['DS_DN']?.toString().trim() ?? '';
    if (dsDn.isEmpty) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al consultar datos de usuario.',
      );
    }
    return dsDn;
  }

  Future<List<BicimadTrip>> fetchTrips({
    required MpassSession session,
    required String email,
    required String nif,
    required String deviceId,
    int? page,
  }) async {
    final response = await _guardNetwork('trips', () {
      BicimadDiagnostics.log('trips', 'request_started', {
        'host': _tripsUri.host,
        'path': _tripsUri.path,
        'method': 'GET',
      });
      final headers = <String, String>{
        ..._authenticatedHeaders(
          accessToken: session.accessToken,
          email: email,
          userId: session.idUser,
          deviceId: deviceId,
        ),
        'language': _apiLanguage,
        'mode': 'mPass',
        'nif': nif,
        'session': session.idUser,
      };
      if (page != null) {
        if (page < 1) {
          throw ArgumentError.value(page, 'page');
        }
        headers['page'] = page.toString();
      }
      return transport.get(_tripsUri, headers: headers);
    });
    final body = _decodeMap(response);
    if (body['code']?.toString() != '00') {
      throw const UnexpectedResponseException(
        'No se han podido descargar los viajes.',
      );
    }
    final data = body['data'];
    if (data is! List) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al descargar viajes.',
      );
    }
    return [
      for (final item in data)
        if (item is Map) _parseTrip(Map<String, Object?>.from(item)),
    ];
  }

  Map<String, String> _authenticatedHeaders({
    required String accessToken,
    required String email,
    required String userId,
    required String deviceId,
  }) {
    return {
      'accessToken': accessToken,
      'appName': _appName,
      'appPlatform': _appPlatform,
      'appPlatformVersion': _appPlatformVersion,
      'appVersion': _appVersion,
      'deviceId': deviceId,
      'deviceModel': _deviceModel,
      'email': email,
      'language': _apiLanguage,
      'userId': userId,
    };
  }

  Map<String, Object?> _decodeMap(HttpResponseData response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const UnexpectedResponseException('Respuesta HTTP no válida.');
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      throw const UnexpectedResponseException('Respuesta JSON no válida.');
    }
    throw const UnexpectedResponseException('Respuesta JSON no válida.');
  }

  BicimadTrip _parseTrip(Map<String, Object?> item) {
    final undock = item['undock'];
    final dock = item['dock'];
    if (undock is! Map || dock is! Map) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al normalizar viajes.',
      );
    }
    final undockMap = Map<String, Object?>.from(undock);
    final dockMap = Map<String, Object?>.from(dock);
    return BicimadTrip(
      externalId: _requiredString(item['trip_id']),
      originStationNumber: _requiredString(undockMap['undock_station_number']),
      originStationName: _nullableStationName(undockMap['undock_station_name']),
      destinationStationNumber: _requiredString(dockMap['dock_station_number']),
      destinationStationName: _nullableStationName(
        dockMap['dock_station_name'],
      ),
      startedAt: _requiredDate(undockMap['undock_ts']),
      endedAt: _requiredDate(dockMap['dock_ts']),
      durationMinutes: _requiredDouble(item['trip_minutes']),
      durationText: _requiredString(item['trip_interval']),
      bikeId: normalizeBikeId(item['id_bike']),
      tripCost: _nullableDecimal(item['trip_cost']),
    );
  }

  String? _nullableDecimal(Object? value) {
    try {
      return normalizeDecimalAmount(value);
    } on FormatException {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al normalizar viajes.',
      );
    }
  }

  String _requiredString(Object? value) {
    final result = value?.toString() ?? '';
    if (result.isEmpty) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al normalizar viajes.',
      );
    }
    return result;
  }

  String? _nullableStationName(Object? value) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? null : result;
  }

  DateTime _requiredDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al normalizar viajes.',
      );
    }
    return parsed;
  }

  double _requiredDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw const UnexpectedResponseException(
        'Respuesta inesperada al normalizar viajes.',
      );
    }
    return parsed;
  }

  Future<HttpResponseData> _guardNetwork(
    String stage,
    Future<HttpResponseData> Function() request,
  ) async {
    try {
      return await request();
    } on TimeoutException catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const NetworkException('Error de conexión con BiciMAD.');
    } on SocketException catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const NetworkException('Error de conexión con BiciMAD.');
    } on HandshakeException catch (error) {
      BicimadDiagnostics.log(stage, 'error', {
        'type': 'HandshakeException',
        'reason': _classifyHandshake(error),
        'osCode': error.osError?.errorCode ?? 'none',
      });
      throw const NetworkException('Error de conexión con BiciMAD.');
    } on http.ClientException catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const NetworkException('Error de conexión con BiciMAD.');
    } on FormatException catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const LoginPreparationException(
        'No se ha podido preparar la petición de login.',
      );
    } on StateError catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const LoginPreparationException(
        'No se ha podido preparar la petición de login.',
      );
    } on ArgumentError catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const LoginPreparationException(
        'No se ha podido preparar la petición de login.',
      );
    } on Object catch (error) {
      BicimadDiagnostics.error(stage, error);
      throw const LoginPreparationException(
        'No se ha podido preparar la petición de login.',
      );
    }
  }

  String _apiCode(HttpResponseData response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final code = decoded['code'];
        if (code == null) return 'none';
        // Only log the documented short numeric code, never arbitrary body text.
        return code is String && RegExp(r'^[0-9]{2}$').hasMatch(code)
            ? code
            : 'unexpected_code';
      }
    } on FormatException {
      return 'invalid_json';
    }
    return 'none';
  }

  String _classifyHandshake(HandshakeException error) {
    final message = [
      error.message,
      error.osError?.message,
    ].whereType<String>().join(' ').toLowerCase();

    if (message.contains('unable to get local issuer') ||
        message.contains('unable to get issuer')) {
      return 'unable_to_get_issuer';
    }
    if (message.contains('missing intermediate') ||
        message.contains('intermediate certificate')) {
      return 'missing_intermediate';
    }
    if (message.contains('self signed')) {
      return 'self_signed_certificate';
    }
    if (message.contains('hostname mismatch') ||
        message.contains('host name mismatch') ||
        message.contains('certificate is not valid for') ||
        message.contains('no alternative certificate subject name')) {
      return 'hostname_mismatch';
    }
    if (message.contains('certificate has expired') ||
        message.contains('certificate expired') ||
        message.contains('expired certificate')) {
      return 'certificate_expired';
    }
    if (message.contains('not yet valid')) {
      return 'certificate_not_yet_valid';
    }
    if (message.contains('unknown ca') || message.contains('unknown_ca')) {
      return 'unknown_ca';
    }
    if (message.contains('certificate_verify_failed') ||
        message.contains('certificate verify failed')) {
      return 'certificate_verify_failed';
    }
    if (message.contains('protocol version')) {
      return 'protocol_version';
    }
    if (message.contains('handshake failure') ||
        message.contains('handshake_failure')) {
      return 'handshake_failure';
    }
    if (message.contains('connection closed') ||
        message.contains('closed during handshake') ||
        message.contains('connection terminated during handshake')) {
      return 'connection_closed_during_handshake';
    }
    return 'other';
  }
}
