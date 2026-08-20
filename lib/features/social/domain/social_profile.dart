class SocialProfile {
  const SocialProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.isPublic,
    this.outgoingFollowStatus,
    this.followsCurrentUser = false,
  });

  final String userId;
  final String username;
  final String displayName;
  final String avatarKey;
  final bool isPublic;
  final FollowStatus? outgoingFollowStatus;
  final bool followsCurrentUser;

  String get avatarAsset => 'assets/avatar/$avatarKey';

  SocialProfile copyWith({
    String? displayName,
    String? avatarKey,
    bool? isPublic,
    FollowStatus? outgoingFollowStatus,
    bool clearOutgoingFollowStatus = false,
    bool? followsCurrentUser,
  }) {
    return SocialProfile(
      userId: userId,
      username: username,
      displayName: displayName ?? this.displayName,
      avatarKey: avatarKey ?? this.avatarKey,
      isPublic: isPublic ?? this.isPublic,
      outgoingFollowStatus: clearOutgoingFollowStatus
          ? null
          : outgoingFollowStatus ?? this.outgoingFollowStatus,
      followsCurrentUser: followsCurrentUser ?? this.followsCurrentUser,
    );
  }

  Map<String, Object?> toJson() => {
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'avatarKey': avatarKey,
    'isPublic': isPublic,
  };

  static SocialProfile? fromJson(Map<String, Object?> json) {
    final userId = json['userId'];
    final username = json['username'];
    final displayName = json['displayName'];
    final avatarKey = json['avatarKey'];
    final isPublic = json['isPublic'];
    if (userId is! String ||
        username is! String ||
        displayName is! String ||
        avatarKey is! String ||
        isPublic is! bool) {
      return null;
    }
    return SocialProfile(
      userId: userId,
      username: username,
      displayName: displayName,
      avatarKey: avatarKey,
      isPublic: isPublic,
    );
  }
}

enum FollowStatus { pending, accepted }

FollowStatus? parseFollowStatus(Object? value) {
  return switch (value?.toString()) {
    'pending' => FollowStatus.pending,
    'accepted' => FollowStatus.accepted,
    _ => null,
  };
}
