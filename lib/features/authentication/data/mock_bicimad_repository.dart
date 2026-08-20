import '../../../core/errors/app_exception.dart';
import '../../trips/data/mock_bicimad_data.dart';
import '../../trips/domain/trip.dart';
import '../domain/bicimad_repository.dart';
import '../domain/mpass_session.dart';

class MockBicimadRepository implements BicimadRepository {
  DateTime? _lastAutomaticSyncAt;
  String? _rememberedEmail;

  @override
  Future<MpassSession> login({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthenticationException(
        'Introduce usuario y contrasena de MPass.',
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    _rememberedEmail = email.trim();

    return MpassSession(
      accessToken: 'mock-access-token',
      idUser: mockCurrentExternalUserId,
      tokenSecExpiration: 3600,
      obtainedAt: DateTime.now(),
    );
  }

  @override
  Future<List<Trip>> fetchTrips(MpassSession session, {int? page}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return mockTrips.where((trip) => trip.userId == mockCurrentUserId).toList();
  }

  @override
  Future<DateTime?> readLastAutomaticSyncAt() async {
    return _lastAutomaticSyncAt;
  }

  @override
  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) async {
    _lastAutomaticSyncAt = syncedAt;
  }

  @override
  Future<String?> readRememberedEmail() async {
    return _rememberedEmail;
  }

  @override
  Future<void> clearSession() async {
    _lastAutomaticSyncAt = null;
  }

  @override
  Future<void> disconnect() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _lastAutomaticSyncAt = null;
  }

  @override
  Future<MpassSession?> restoreSession() async {
    return null;
  }
}
