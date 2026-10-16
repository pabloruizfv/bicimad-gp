import '../../trips/domain/community_repository.dart';
import '../../trips/domain/trip.dart';
import '../../trips/domain/trip_elevation.dart';
import '../../trips/domain/trip_eligibility.dart';
import '../domain/social_repository.dart';

class SocialTripSyncService {
  const SocialTripSyncService({
    required this.socialRepository,
    required this.localRepository,
    this.loadElevationCalculator,
  });

  final SocialRepository socialRepository;
  final CommunityRepository localRepository;
  final Future<TripElevationCalculator> Function()? loadElevationCalculator;

  Future<SocialTripSyncResult> synchronize({
    required String normalizedMpassEmail,
    required String mpassUserId,
  }) async {
    final downloaded = await pullCloudHistory(
      normalizedMpassEmail: normalizedMpassEmail,
      mpassUserId: mpassUserId,
    );
    if (downloaded == null) {
      return const SocialTripSyncResult.skipped();
    }
    final uploaded = await pushLocalHistory(
      normalizedMpassEmail: normalizedMpassEmail,
    );
    return SocialTripSyncResult(
      downloaded: downloaded,
      uploaded: uploaded ?? 0,
      skipped: false,
    );
  }

  Future<int?> pullCloudHistory({
    required String normalizedMpassEmail,
    required String mpassUserId,
  }) async {
    if (!await _validateIdentity(normalizedMpassEmail)) {
      return null;
    }
    final cloudTrips = await socialRepository.getOwnTrips(
      localUserId: mpassUserId,
    );
    final countableTrips = cloudTrips
        .where(isCountableBicimadStage)
        .toList(growable: false);
    await localRepository.replaceMyTrips(countableTrips);
    return countableTrips.length;
  }

  Future<int?> pushLocalHistory({required String normalizedMpassEmail}) async {
    if (!await _validateIdentity(normalizedMpassEmail)) {
      return null;
    }
    final mergedStages = await localRepository.getMyStages();
    await socialRepository.upsertOwnTrips(
      await _withNetElevations(mergedStages),
    );
    await socialRepository.refreshOwnAchievements();
    return mergedStages.length;
  }

  Future<int?> pushTripBatch({
    required String normalizedMpassEmail,
    required List<Trip> trips,
  }) async {
    final countableTrips = trips
        .where(isCountableBicimadStage)
        .toList(growable: false);
    if (countableTrips.isEmpty ||
        !await _validateIdentity(normalizedMpassEmail)) {
      return null;
    }
    await socialRepository.upsertOwnTrips(
      await _withNetElevations(countableTrips),
    );
    return countableTrips.length;
  }

  Future<bool> _validateIdentity(String normalizedMpassEmail) async {
    if (!socialRepository.hasSession) {
      return false;
    }
    final socialEmail = normalizeEmail(socialRepository.currentEmail);
    if (socialEmail == null || socialEmail != normalizedMpassEmail) {
      await socialRepository.signOut();
      throw const SocialIdentityMismatchException();
    }
    return true;
  }

  Future<List<Trip>> _withNetElevations(List<Trip> trips) async {
    final loader = loadElevationCalculator;
    if (loader == null) return trips;
    final calculator = await loader();
    return [
      for (final trip in trips)
        trip.copyWith(
          netElevationMeters: calculator.forTrip(trip).netMeters,
        ),
    ];
  }
}

class SocialTripSyncResult {
  const SocialTripSyncResult({
    required this.downloaded,
    required this.uploaded,
    required this.skipped,
  });

  const SocialTripSyncResult.skipped()
    : downloaded = 0,
      uploaded = 0,
      skipped = true;

  final int downloaded;
  final int uploaded;
  final bool skipped;
}

class SocialIdentityMismatchException implements Exception {
  const SocialIdentityMismatchException();
}

String? normalizeEmail(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
