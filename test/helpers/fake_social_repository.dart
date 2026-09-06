import 'package:bicimad_social/features/social/domain/follow_connection.dart';
import 'package:bicimad_social/features/social/domain/profile_statistics.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/social/domain/social_repository.dart';
import 'package:bicimad_social/features/achievements/domain/achievement.dart';
import 'package:bicimad_social/features/achievements/domain/achievement_ranking.dart';
import 'package:bicimad_social/features/rankings/domain/community_route_ranking.dart';
import 'package:bicimad_social/features/rankings/domain/head_to_head.dart';
import 'package:bicimad_social/features/rankings/domain/route_key.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';

class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository({
    this.configured = true,
    this.session = true,
    this.userId = 'social-user-1',
    this.email = 'pablo@example.com',
    this.profile = const SocialProfile(
      userId: 'social-user-1',
      username: 'pablo_test',
      displayName: 'Pablo',
      avatarKey: '1.png',
      isPublic: true,
    ),
    List<Trip> ownTrips = const [],
    List<UserAchievement> achievements = const [],
    Map<String, AchievementCommunityRanking> achievementRankings = const {},
    Map<RouteKey, CommunityRouteRanking> communityRouteRankings = const {},
    this.sendOtpError,
    this.sendOtpHandler,
    this.restoreSessionHandler,
  }) : ownTrips = [...ownTrips],
       achievements = [...achievements],
       achievementRankings = {...achievementRankings},
       communityRouteRankings = {...communityRouteRankings};

  bool configured;
  bool session;
  String? userId;
  String? email;
  SocialProfile? profile;
  final List<Trip> ownTrips;
  final List<UserAchievement> achievements;
  final Map<String, AchievementCommunityRanking> achievementRankings;
  final Map<RouteKey, CommunityRouteRanking> communityRouteRankings;
  final Object? sendOtpError;
  final Future<void> Function(String email)? sendOtpHandler;
  final Future<bool> Function()? restoreSessionHandler;
  final List<List<Trip>> uploadedTripBatches = [];
  final List<String> sentOtpEmails = [];
  final List<String> verifiedOtpTokens = [];
  final List<String> operations = [];
  int signOutCalls = 0;
  int deleteOwnAccountCalls = 0;

  @override
  bool get isConfigured => configured;

  @override
  String? get currentUserId => session ? userId : null;

  @override
  String? get currentEmail => session ? email : null;

  @override
  bool get hasSession => session;

  @override
  Future<bool> restoreSession() async {
    operations.add('restoreSession');
    final handler = restoreSessionHandler;
    return handler == null ? session : handler();
  }

  @override
  Future<void> sendOtp(String normalizedEmail) async {
    operations.add('sendOtp');
    sentOtpEmails.add(normalizedEmail);
    final error = sendOtpError;
    if (error != null) {
      throw error;
    }
    await sendOtpHandler?.call(normalizedEmail);
  }

  @override
  Future<void> verifyOtp({
    required String normalizedEmail,
    required String token,
  }) async {
    operations.add('verifyOtp');
    verifiedOtpTokens.add(token);
    email = normalizedEmail;
    session = true;
  }

  @override
  Future<void> signOut() async {
    operations.add('signOut');
    signOutCalls += 1;
    session = false;
  }

  @override
  Future<void> deleteOwnAccount() async {
    operations.add('deleteOwnAccount');
    deleteOwnAccountCalls += 1;
    ownTrips.clear();
    profile = null;
    session = false;
  }

  @override
  Future<SocialProfile?> getMyProfile() async {
    operations.add('getMyProfile');
    return profile;
  }

  @override
  Future<SocialProfile> createProfile({
    required String username,
    required String displayName,
    required String avatarKey,
    required bool isPublic,
    required String? mpassUserId,
  }) async {
    operations.add('createProfile');
    return profile = SocialProfile(
      userId: userId!,
      username: username,
      displayName: displayName,
      avatarKey: avatarKey,
      isPublic: isPublic,
    );
  }

  @override
  Future<SocialProfile> updateProfile({
    required String displayName,
    required String avatarKey,
    required bool isPublic,
  }) async {
    operations.add('updateProfile');
    final current = profile!;
    return profile = current.copyWith(
      displayName: displayName,
      avatarKey: avatarKey,
      isPublic: isPublic,
    );
  }

  @override
  Future<List<SocialProfile>> searchProfiles(String query) async => const [];

  @override
  Future<SocialProfileDetails?> getProfileDetails(String userId) async => null;

  @override
  Future<List<FollowConnection>> getConnections(
    ConnectionListType type,
  ) async => const [];

  @override
  Future<void> follow(String userId) async => operations.add('follow');

  @override
  Future<void> acceptFollow(String userId) async =>
      operations.add('acceptFollow');

  @override
  Future<void> rejectFollow(String userId) async =>
      operations.add('rejectFollow');

  @override
  Future<void> cancelFollow(String userId) async =>
      operations.add('cancelFollow');

  @override
  Future<void> unfollow(String userId) async => operations.add('unfollow');

  @override
  Future<void> removeFollower(String userId) async =>
      operations.add('removeFollower');

  @override
  Future<List<Trip>> getOwnTrips({required String localUserId}) async {
    operations.add('getOwnTrips');
    return [for (final trip in ownTrips) trip.copyWith(userId: localUserId)];
  }

  @override
  Future<void> upsertOwnTrips(List<Trip> trips) async {
    operations.add('upsertOwnTrips');
    uploadedTripBatches.add([...trips]);
  }

  @override
  Future<List<UserAchievement>> getUserAchievements(String userId) async {
    operations.add('getUserAchievements');
    return [...achievements];
  }

  @override
  Future<AchievementCommunityRanking> getAchievementRanking(
    String categoryId,
  ) async {
    operations.add('getAchievementRanking:$categoryId');
    return achievementRankings[categoryId] ??
        AchievementCommunityRanking(
          categoryId: categoryId,
          entries: const [],
          totalUsers: 0,
        );
  }

  @override
  Future<CommunityRouteRanking> getCommunityRouteRanking({
    required String originStationId,
    required String destinationStationId,
  }) async {
    operations.add('getCommunityRouteRanking');
    return communityRouteRankings[RouteKey(
          originStationId: originStationId,
          destinationStationId: destinationStationId,
        )] ??
        const CommunityRouteRanking(entries: []);
  }

  @override
  Future<HeadToHeadSummary> getHeadToHead(String otherUserId) async {
    operations.add('getHeadToHead');
    return const HeadToHeadSummary(entries: []);
  }

  @override
  Future<void> refreshOwnAchievements() async {
    operations.add('refreshOwnAchievements');
  }
}
