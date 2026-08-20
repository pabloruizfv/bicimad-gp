class MpassSession {
  const MpassSession({
    required this.accessToken,
    required this.idUser,
    required this.tokenSecExpiration,
    required this.obtainedAt,
  });

  final String accessToken;
  final String idUser;
  final int tokenSecExpiration;
  final DateTime obtainedAt;

  String get id => idUser;

  String get externalUserId => idUser;

  DateTime get createdAt => obtainedAt;

  DateTime get expiresAt =>
      obtainedAt.add(Duration(seconds: tokenSecExpiration));

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}
