import '../../../core/errors/app_exception.dart';
import '../../trips/data/mock_bicimad_data.dart';
import '../../trips/domain/trip.dart';
import '../domain/bicimad_repository.dart';
import '../domain/bicimad_session.dart';

class MockBicimadRepository implements BicimadRepository {
  @override
  Future<BicimadSession> login({
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const AuthenticationException(
        'Introduce usuario y contrasena de MPass.',
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));

    return BicimadSession(
      id: 'mock-session-${DateTime.now().millisecondsSinceEpoch}',
      externalUserId: mockCurrentExternalUserId,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<Trip>> fetchTrips(BicimadSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return mockTrips.where((trip) => trip.userId == mockCurrentUserId).toList();
  }

  @override
  Future<void> disconnect() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}
