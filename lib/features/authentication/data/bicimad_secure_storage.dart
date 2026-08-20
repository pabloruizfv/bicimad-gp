import 'dart:math';

import '../../../core/diagnostics/bicimad_diagnostics.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/storage/secure_key_value_store.dart';
import '../domain/mpass_session.dart';

class TechnicalConfig {
  const TechnicalConfig({required this.passKey, required this.xClientId});

  final String passKey;
  final String xClientId;
}

class BicimadSecureStorage {
  BicimadSecureStorage({required this.store, Random? random})
    : _random = random ?? Random.secure();

  static const passKeyKey = 'technical.passKey';
  static const xClientIdKey = 'technical.xClientId';
  static const deviceIdKey = 'device.id';
  static const accessTokenKey = 'session.accessToken';
  static const idUserKey = 'session.idUser';
  static const emailKey = 'session.email';
  static const obtainedAtKey = 'session.obtainedAt';
  static const tokenSecExpirationKey = 'session.tokenSecExpiration';
  static const lastAutomaticSyncAtKey = 'sync.lastAutomaticAt';
  static const rememberedEmailKey = 'login.rememberedEmail';

  final SecureKeyValueStore store;
  final Random _random;

  Future<void> saveTechnicalConfig({
    required String passKey,
    required String xClientId,
  }) async {
    await store.write(key: passKeyKey, value: passKey);
    await store.write(key: xClientIdKey, value: xClientId);
  }

  Future<TechnicalConfig?> readTechnicalConfig() async {
    final passKey = await store.read(passKeyKey);
    final xClientId = await store.read(xClientIdKey);
    if (passKey == null ||
        passKey.trim().isEmpty ||
        xClientId == null ||
        xClientId.trim().isEmpty) {
      return null;
    }
    return TechnicalConfig(passKey: passKey, xClientId: xClientId);
  }

  Future<bool> hasTechnicalConfig() async {
    return await readTechnicalConfig() != null;
  }

  Future<void> clearTechnicalConfig() async {
    await store.delete(passKeyKey);
    await store.delete(xClientIdKey);
  }

  Future<String> getOrCreateDeviceId() async {
    try {
      BicimadDiagnostics.log('device_id', 'read_started');
      final existing = await store.read(deviceIdKey);
      final hasExisting = existing != null && _isValidDeviceId(existing);
      BicimadDiagnostics.log('device_id', 'read_completed', {
        'existing': hasExisting,
      });
      if (hasExisting) {
        return existing;
      }
      BicimadDiagnostics.log('device_id', 'create_started');
      final generated = _generateDeviceId();
      await store.write(key: deviceIdKey, value: generated);
      BicimadDiagnostics.log('device_id', 'create_completed');
      return generated;
    } on SecureStorageException catch (error) {
      BicimadDiagnostics.error('device_id', error);
      rethrow;
    } on Object catch (error) {
      BicimadDiagnostics.error('device_id', error);
      throw const SecureStorageException(
        'No se ha podido acceder al almacenamiento seguro.',
      );
    }
  }

  Future<void> saveSession({
    required MpassSession session,
    required String email,
  }) async {
    await store.write(key: rememberedEmailKey, value: email);
    await store.write(key: accessTokenKey, value: session.accessToken);
    await store.write(key: idUserKey, value: session.idUser);
    await store.write(key: emailKey, value: email);
    await store.write(
      key: obtainedAtKey,
      value: session.obtainedAt.toIso8601String(),
    );
    await store.write(
      key: tokenSecExpirationKey,
      value: session.tokenSecExpiration.toString(),
    );
  }

  Future<StoredMpassSession?> readSession() async {
    try {
      BicimadDiagnostics.log('session', 'read_started');
      final accessToken = await store.read(accessTokenKey);
      final idUser = await store.read(idUserKey);
      final email = await store.read(emailKey);
      final obtainedAtValue = await store.read(obtainedAtKey);
      final expirationValue = await store.read(tokenSecExpirationKey);
      final obtainedAt = obtainedAtValue == null
          ? null
          : DateTime.tryParse(obtainedAtValue);
      final tokenSecExpiration = expirationValue == null
          ? null
          : int.tryParse(expirationValue);

      if (accessToken == null ||
          accessToken.isEmpty ||
          idUser == null ||
          idUser.isEmpty ||
          email == null ||
          email.isEmpty ||
          obtainedAt == null ||
          tokenSecExpiration == null) {
        BicimadDiagnostics.log('session', 'read_completed', {
          'existing': false,
          'valid': false,
        });
        return null;
      }

      final session = MpassSession(
        accessToken: accessToken,
        idUser: idUser,
        tokenSecExpiration: tokenSecExpiration,
        obtainedAt: obtainedAt,
      );
      BicimadDiagnostics.log('session', 'read_completed', {
        'existing': true,
        'valid': !session.isExpiredAt(DateTime.now()),
      });

      return StoredMpassSession(session: session, email: email);
    } on SecureStorageException catch (error) {
      BicimadDiagnostics.error('session', error);
      rethrow;
    } on Object catch (error) {
      BicimadDiagnostics.error('session', error);
      throw const SecureStorageException(
        'No se ha podido acceder al almacenamiento seguro.',
      );
    }
  }

  Future<void> clearSession() async {
    await store.delete(accessTokenKey);
    await store.delete(idUserKey);
    await store.delete(emailKey);
    await store.delete(obtainedAtKey);
    await store.delete(tokenSecExpirationKey);
    await store.delete(lastAutomaticSyncAtKey);
  }

  Future<void> clearPersonalData() async {
    await clearSession();
    await store.delete(rememberedEmailKey);
    await store.delete(deviceIdKey);
  }

  Future<DateTime?> readLastAutomaticSyncAt() async {
    final value = await store.read(lastAutomaticSyncAtKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) async {
    await store.write(
      key: lastAutomaticSyncAtKey,
      value: syncedAt.toIso8601String(),
    );
  }

  Future<String?> readRememberedEmail() async {
    final email = await store.read(rememberedEmailKey);
    if (email == null || email.trim().isEmpty) {
      return null;
    }
    return email.trim();
  }

  String _generateDeviceId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  bool _isValidDeviceId(String value) {
    return RegExp(r'^[0-9a-f]{16}$').hasMatch(value);
  }
}

class StoredMpassSession {
  const StoredMpassSession({required this.session, required this.email});

  final MpassSession session;
  final String email;
}
