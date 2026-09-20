import 'package:flutter/services.dart';

import '../../../core/storage/secure_key_value_store.dart';

abstract interface class AvatarRepository {
  Future<String> readSelectedAvatar();

  Future<void> saveSelectedAvatar(String assetPath);

  Future<void> clearSelectedAvatar();
}

class LocalAvatarRepository implements AvatarRepository {
  const LocalAvatarRepository({required this.store});

  static const defaultAvatarAsset = 'assets/avatar/1.png';
  static const _storageKey = 'profile.avatarAsset.v1';
  static Future<List<String>>? _avatarAssetsFuture;

  final SecureKeyValueStore store;

  static Future<List<String>> loadAvatarAssets() {
    return _avatarAssetsFuture ??= _readAvatarAssets();
  }

  static Future<List<String>> _readAvatarAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest
            .listAssets()
            .where(
              (asset) => RegExp(r'^assets/avatar/\d+\.png$').hasMatch(asset),
            )
            .toList()
          ..sort((left, right) {
            final leftNumber = int.parse(left.split('/').last.split('.').first);
            final rightNumber = int.parse(
              right.split('/').last.split('.').first,
            );
            return leftNumber.compareTo(rightNumber);
          });
    return List.unmodifiable(assets);
  }

  static bool isAvatarAsset(String assetPath) {
    return RegExp(r'^assets/avatar/\d+\.png$').hasMatch(assetPath);
  }

  @override
  Future<String> readSelectedAvatar() async {
    final value = await store.read(_storageKey);
    if (value != null && isAvatarAsset(value)) {
      return value;
    }
    return defaultAvatarAsset;
  }

  @override
  Future<void> saveSelectedAvatar(String assetPath) async {
    if (!isAvatarAsset(assetPath)) {
      throw ArgumentError.value(assetPath, 'assetPath');
    }
    await store.write(key: _storageKey, value: assetPath);
  }

  @override
  Future<void> clearSelectedAvatar() => store.delete(_storageKey);
}
