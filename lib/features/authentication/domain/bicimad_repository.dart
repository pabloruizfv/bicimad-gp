import '../../trips/domain/trip.dart';
import 'mpass_session.dart';

abstract interface class BicimadRepository {
  Future<MpassSession> login({required String email, required String password});

  Future<MpassSession?> restoreSession();

  Future<List<Trip>> fetchTrips(MpassSession session, {int? page});

  Future<DateTime?> readLastAutomaticSyncAt();

  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt);

  Future<String?> readRememberedEmail();

  Future<void> clearSession();

  Future<void> disconnect();
}
