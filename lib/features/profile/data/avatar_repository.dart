import '../../../core/storage/secure_key_value_store.dart';

abstract interface class AvatarRepository {
  Future<String> readSelectedAvatar();

  Future<void> saveSelectedAvatar(String assetPath);

  Future<void> clearSelectedAvatar();
}

class LocalAvatarRepository implements AvatarRepository {
  const LocalAvatarRepository({required this.store});

  static const avatarAssets = [
    'assets/avatar/1.png',
    'assets/avatar/2.png',
    'assets/avatar/3.png',
    'assets/avatar/4.png',
    'assets/avatar/5.png',
    'assets/avatar/6.png',
    'assets/avatar/7.png',
    'assets/avatar/8.png',
    'assets/avatar/9.png',
    'assets/avatar/10.png',
    'assets/avatar/11.png',
    'assets/avatar/12.png',
  ];
  static const defaultAvatarAsset = 'assets/avatar/1.png';
  static const _storageKey = 'profile.avatarAsset.v1';

  final SecureKeyValueStore store;

  @override
  Future<String> readSelectedAvatar() async {
    final value = await store.read(_storageKey);
    if (value != null && avatarAssets.contains(value)) {
      return value;
    }
    return defaultAvatarAsset;
  }

  @override
  Future<void> saveSelectedAvatar(String assetPath) async {
    if (!avatarAssets.contains(assetPath)) {
      throw ArgumentError.value(assetPath, 'assetPath');
    }
    await store.write(key: _storageKey, value: assetPath);
  }

  @override
  Future<void> clearSelectedAvatar() => store.delete(_storageKey);
}
