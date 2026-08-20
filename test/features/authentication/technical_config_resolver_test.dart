import 'package:bicimad_social/core/config/bicimad_build_config.dart';
import 'package:bicimad_social/features/authentication/data/bicimad_secure_storage.dart';
import 'package:bicimad_social/features/authentication/data/technical_config_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test(
    'usa ambos valores presentes en la configuracion de compilacion',
    () async {
      final store = InMemorySecureKeyValueStore();
      final resolver = _resolver(
        store: store,
        buildConfig: const BicimadBuildConfig(
          passKey: 'build-pass-key',
          xClientId: 'build-client-id',
        ),
      );

      final resolved = await resolver.resolve();

      expect(resolved.source, TechnicalConfigSource.build);
      expect(resolved.config?.passKey, 'build-pass-key');
      expect(resolved.config?.xClientId, 'build-client-id');
    },
  );

  test('no consulta secure storage si build esta completa', () async {
    final store = InMemorySecureKeyValueStore();
    await BicimadSecureStorage(store: store).saveTechnicalConfig(
      passKey: 'stored-pass-key',
      xClientId: 'stored-client-id',
    );
    store.readKeys.clear();
    final resolver = _resolver(
      store: store,
      buildConfig: const BicimadBuildConfig(
        passKey: 'build-pass-key',
        xClientId: 'build-client-id',
      ),
    );

    final resolved = await resolver.resolve();

    expect(resolved.source, TechnicalConfigSource.build);
    expect(store.readKeys, isEmpty);
  });

  test('usa secure storage como fallback cuando build esta ausente', () async {
    final store = InMemorySecureKeyValueStore();
    await BicimadSecureStorage(store: store).saveTechnicalConfig(
      passKey: 'stored-pass-key',
      xClientId: 'stored-client-id',
    );
    final resolver = _resolver(
      store: store,
      buildConfig: const BicimadBuildConfig(passKey: '', xClientId: ''),
    );

    final resolved = await resolver.resolve();

    expect(resolved.source, TechnicalConfigSource.secureStorage);
    expect(resolved.config?.passKey, 'stored-pass-key');
    expect(resolved.config?.xClientId, 'stored-client-id');
  });

  test('build con solo passKey no se mezcla con secure storage', () async {
    final store = InMemorySecureKeyValueStore();
    await store.write(
      key: BicimadSecureStorage.xClientIdKey,
      value: 'stored-client-id',
    );
    final resolver = _resolver(
      store: store,
      buildConfig: const BicimadBuildConfig(
        passKey: 'build-pass-key',
        xClientId: '',
      ),
    );

    final resolved = await resolver.resolve();

    expect(resolved.source, TechnicalConfigSource.missing);
    expect(resolved.config, isNull);
  });

  test('build con solo X-ClientId no se mezcla con secure storage', () async {
    final store = InMemorySecureKeyValueStore();
    await store.write(
      key: BicimadSecureStorage.passKeyKey,
      value: 'stored-pass-key',
    );
    final resolver = _resolver(
      store: store,
      buildConfig: const BicimadBuildConfig(
        passKey: '',
        xClientId: 'build-client-id',
      ),
    );

    final resolved = await resolver.resolve();

    expect(resolved.source, TechnicalConfigSource.missing);
    expect(resolved.config, isNull);
  });

  test('devuelve missing cuando ambas fuentes estan incompletas', () async {
    final resolver = _resolver(
      store: InMemorySecureKeyValueStore(),
      buildConfig: const BicimadBuildConfig(passKey: '', xClientId: ''),
    );

    final resolved = await resolver.resolve();

    expect(resolved.source, TechnicalConfigSource.missing);
    expect(resolved.isConfigured, isFalse);
  });
}

TechnicalConfigResolver _resolver({
  required InMemorySecureKeyValueStore store,
  required BicimadBuildConfig buildConfig,
}) {
  return TechnicalConfigResolver(
    buildConfig: buildConfig,
    secureStorage: BicimadSecureStorage(store: store),
  );
}
