abstract interface class ProfileStatisticsValues {
  int get totalTrips;
  int get historySpanDays;
  int get totalDurationSeconds;
  double get totalDistanceMeters;
  double? get equivalentAverageSpeedKmh;
  int get tripsWithDistance;
}
