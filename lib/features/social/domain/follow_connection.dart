import 'social_profile.dart';

class FollowConnection {
  const FollowConnection({
    required this.profile,
    required this.status,
    required this.direction,
    required this.createdAt,
  });

  final SocialProfile profile;
  final FollowStatus status;
  final FollowDirection direction;
  final DateTime createdAt;
}

enum FollowDirection { incoming, outgoing }

enum ConnectionListType { followers, following, receivedRequests, sentRequests }
