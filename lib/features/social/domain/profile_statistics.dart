import '../../../core/models/profile_statistics_values.dart';
import 'social_profile.dart';

class ProfileStatistics implements ProfileStatisticsValues {
  const ProfileStatistics({
    required this.totalTrips,
    required this.historySpanDays,
    this.distinctTripDays = 0,
    required this.totalDurationSeconds,
    required this.totalDistanceMeters,
    required this.equivalentAverageSpeedKmh,
    required this.tripsWithDistance,
  });

  @override
  final int totalTrips;
  @override
  final int historySpanDays;
  final int distinctTripDays;
  @override
  final int totalDurationSeconds;
  @override
  final double totalDistanceMeters;
  @override
  final double? equivalentAverageSpeedKmh;
  @override
  final int tripsWithDistance;
}

class SocialProfileDetails {
  const SocialProfileDetails({
    required this.profile,
    this.statistics,
    this.followersCount,
    this.followingCount,
  });

  final SocialProfile profile;
  final ProfileStatistics? statistics;
  final int? followersCount;
  final int? followingCount;
}
