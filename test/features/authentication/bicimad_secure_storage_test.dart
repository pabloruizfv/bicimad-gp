import 'package:bicimad_social/features/authentication/data/bicimad_secure_storage.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test('guarda, recupera y elimina la configuracion tecnica', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);

    expect(await storage.readTechnicalConfig(), isNull);
    await storage.saveTechnicalConfig(
      passKey: 'fake-pass-key',
      xClientId: 'fake-client-id',
    );

    final config = await storage.readTechnicalConfig();
    expect(config?.passKey, 'fake-pass-key');
    expect(config?.xClientId, 'fake-client-id');

    await storage.clearTechnicalConfig();
    expect(await storage.readTechnicalConfig(), isNull);
  });

  test('detecta configuracion tecnica incompleta', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);

    await store.write(
      key: BicimadSecureStorage.passKeyKey,
      value: 'fake-pass-key',
    );

    expect(await storage.readTechnicalConfig(), isNull);
  });

  test('genera y reutiliza un deviceId local estable', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);

    final first = await storage.getOrCreateDeviceId();
    final second = await storage.getOrCreateDeviceId();

    expect(first, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(second, first);
  });

  test('guarda sesion valida y permite detectar sesion caducada', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    final obtainedAt = DateTime(2026, 8, 2, 10);

    await storage.saveSession(
      session: MpassSession(
        accessToken: 'fake-token',
        idUser: 'fake-user',
        tokenSecExpiration: 60,
        obtainedAt: obtainedAt,
      ),
      email: 'fake@example.com',
    );

    final stored = await storage.readSession();
    expect(
      stored?.session.isExpiredAt(obtainedAt.add(Duration(seconds: 59))),
      isFalse,
    );
    expect(
      stored?.session.isExpiredAt(obtainedAt.add(Duration(seconds: 60))),
      isTrue,
    );
  });

  test('elimina la sesion sin guardar contrasena ni DS_DN', () async {
    final store = InMemorySecureKeyValueStore();
    final storage = BicimadSecureStorage(store: store);
    final syncedAt = DateTime(2026, 8, 2, 10);

    await storage.saveSession(
      session: MpassSession(
        accessToken: 'fake-token',
        idUser: 'fake-user',
        tokenSecExpiration: 60,
        obtainedAt: DateTime(2026, 8, 2),
      ),
      email: 'fake@example.com',
    );
    await storage.saveLastAutomaticSyncAt(syncedAt);

    expect(store.values.values, isNot(contains('fake-password')));
    expect(store.values.values, isNot(contains('fake-ds-dn')));
    expect(await storage.readLastAutomaticSyncAt(), syncedAt);

    await storage.clearSession();
    expect(await storage.readSession(), isNull);
    expect(await storage.readLastAutomaticSyncAt(), isNull);
  });

  test(
    'el borrado personal elimina correo y deviceId pero no config',
    () async {
      final store = InMemorySecureKeyValueStore();
      final storage = BicimadSecureStorage(store: store);
      await storage.saveTechnicalConfig(
        passKey: 'fake-pass-key',
        xClientId: 'fake-client-id',
      );
      await storage.saveSession(
        session: MpassSession(
          accessToken: 'fake-token',
          idUser: 'fake-user',
          tokenSecExpiration: 60,
          obtainedAt: DateTime(2026, 8, 7),
        ),
        email: 'fake@example.test',
      );
      await storage.getOrCreateDeviceId();

      await storage.clearPersonalData();

      expect(await storage.readSession(), isNull);
      expect(await storage.readRememberedEmail(), isNull);
      expect(store.values, isNot(contains(BicimadSecureStorage.deviceIdKey)));
      expect(await storage.readTechnicalConfig(), isNotNull);
    },
  );
}
