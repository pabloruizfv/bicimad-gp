import '../../trips/domain/trip.dart';
import 'follow_connection.dart';
import 'profile_statistics.dart';
import 'social_profile.dart';

abstract interface class SocialRepository {
  bool get isConfigured;

  String? get currentUserId;

  String? get currentEmail;

  bool get hasSession;

  Future<bool> restoreSession();

  Future<void> sendOtp(String normalizedEmail);

  Future<void> verifyOtp({
    required String normalizedEmail,
    required String token,
  });

  Future<void> signOut();

  Future<void> deleteOwnAccount();

  Future<SocialProfile?> getMyProfile();

  Future<SocialProfile> createProfile({
    required String username,
    required String displayName,
    required String avatarKey,
    required bool isPublic,
    required String? mpassUserId,
  });

  Future<SocialProfile> updateProfile({
    required String displayName,
    required String avatarKey,
    required bool isPublic,
  });

  Future<List<SocialProfile>> searchProfiles(String query);

  Future<SocialProfileDetails?> getProfileDetails(String userId);

  Future<List<FollowConnection>> getConnections(ConnectionListType type);

  Future<void> follow(String userId);

  Future<void> acceptFollow(String userId);

  Future<void> rejectFollow(String userId);

  Future<void> cancelFollow(String userId);

  Future<void> unfollow(String userId);

  Future<void> removeFollower(String userId);

  Future<List<Trip>> getOwnTrips({required String localUserId});

  Future<void> upsertOwnTrips(List<Trip> trips);
}

enum SocialAuthFailureKind {
  emailNotAuthorized,
  rateLimited,
  otpDisabled,
  signupDisabled,
  invalidEmail,
  secureConnection,
  connection,
  serviceUnavailable,
  unexpectedResponse,
}

class SocialAuthFailure implements Exception {
  const SocialAuthFailure(this.kind);

  final SocialAuthFailureKind kind;
}
