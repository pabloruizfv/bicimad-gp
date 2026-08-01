class BicimadSession {
  const BicimadSession({
    required this.id,
    required this.externalUserId,
    required this.createdAt,
  });

  final String id;
  final String externalUserId;
  final DateTime createdAt;
}
