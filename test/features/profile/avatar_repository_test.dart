import 'package:bicimad_social/features/profile/data/avatar_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test('guarda y recupera el avatar seleccionado localmente', () async {
    final store = InMemorySecureKeyValueStore();
    final repository = LocalAvatarRepository(store: store);

    expect(
      await repository.readSelectedAvatar(),
      LocalAvatarRepository.defaultAvatarAsset,
    );

    await repository.saveSelectedAvatar('assets/avatar/3.png');

    expect(await repository.readSelectedAvatar(), 'assets/avatar/3.png');
    expect(store.values.values, isNot(contains('email')));
  });

  test(
    'elimina la seleccion personal y recupera el avatar por defecto',
    () async {
      final store = InMemorySecureKeyValueStore();
      final repository = LocalAvatarRepository(store: store);
      await repository.saveSelectedAvatar('assets/avatar/4.png');

      await repository.clearSelectedAvatar();

      expect(
        await repository.readSelectedAvatar(),
        LocalAvatarRepository.defaultAvatarAsset,
      );
    },
  );

  test('permite seleccionar el avatar 12', () async {
    final store = InMemorySecureKeyValueStore();
    final repository = LocalAvatarRepository(store: store);

    await repository.saveSelectedAvatar('assets/avatar/12.png');

    expect(await repository.readSelectedAvatar(), 'assets/avatar/12.png');
  });
}
