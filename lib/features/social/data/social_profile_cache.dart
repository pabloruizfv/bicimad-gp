import 'dart:convert';

import '../../../core/storage/secure_key_value_store.dart';
import '../domain/social_profile.dart';

class SocialProfileCache {
  const SocialProfileCache({required this.store});

  static const _key = 'social.profile.cache.v1';

  final SecureKeyValueStore store;

  Future<SocialProfile?> read(String userId) async {
    final raw = await store.read(_key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final profile = SocialProfile.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return profile?.userId == userId ? profile : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(SocialProfile profile) {
    return store.write(key: _key, value: jsonEncode(profile.toJson()));
  }

  Future<void> clear() => store.delete(_key);
}
