class CommunityUser {
  const CommunityUser({
    required this.id,
    required this.externalUserId,
    required this.displayName,
    required this.createdAt,
  });

  final String id;
  final String externalUserId;
  final String displayName;
  final DateTime createdAt;

  CommunityUser copyWith({String? displayName}) {
    return CommunityUser(
      id: id,
      externalUserId: externalUserId,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt,
    );
  }
}
