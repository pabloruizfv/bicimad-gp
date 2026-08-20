import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/authentication/domain/bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:bicimad_social/features/trips/data/local_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restoreSession no repite auto-sync si sincronizo hace menos de 1h',
    () async {
      final now = DateTime(2026, 8, 2, 12);
      final repository = _FakeBicimadRepository(
        session: _session(),
        lastAutomaticSyncAt: DateTime(2026, 8, 2, 11, 15),
      );
      final communityRepository = LocalCommunityRepository();
      await communityRepository.createOrRecoverUser(externalUserId: 'user-1');
      await communityRepository.replaceMyTrips([
        _trip('existing', DateTime(2026, 8, 2, 7)),
      ]);

      final controller = AuthController(
        repository,
        communityRepository,
        now: () => now,
      );
      await _waitForRestore(controller);

      expect(repository.fetchCount, 0);
      expect(controller.state.lastSyncAt, DateTime(2026, 8, 2, 11, 15));
    },
  );

  test(
    'restoreSession sincroniza automaticamente si el ultimo sync fue hace mas de 1h',
    () async {
      final now = DateTime(2026, 8, 2, 12);
      final repository = _FakeBicimadRepository(
        session: _session(),
        lastAutomaticSyncAt: DateTime(2026, 8, 2, 10, 59),
      );
      final communityRepository = LocalCommunityRepository();
      await communityRepository.createOrRecoverUser(externalUserId: 'user-1');
      await communityRepository.replaceMyTrips([
        _trip('existing', DateTime(2026, 8, 1, 7)),
      ]);

      final controller = AuthController(
        repository,
        communityRepository,
        now: () => now,
      );
      await _waitForRestore(controller);

      expect(repository.fetchCount, 1);
      expect(repository.lastAutomaticSyncAt, now);
      expect(controller.state.lastSyncAt, now);
    },
  );

  test(
    'restoreSession sincroniza si no hay viajes cargados localmente',
    () async {
      final now = DateTime(2026, 8, 2, 12);
      final repository = _FakeBicimadRepository(
        session: _session(),
        lastAutomaticSyncAt: DateTime(2026, 8, 2, 8),
      );

      final controller = AuthController(
        repository,
        LocalCommunityRepository(),
        now: () => now,
      );
      await _waitForRestore(controller);

      expect(repository.fetchCount, 1);
      expect(repository.lastAutomaticSyncAt, now);
    },
  );

  test('cerrar sesion conserva la sesion social del dispositivo', () async {
    final repository = _FakeBicimadRepository(session: _session());
    var socialSignOutCalls = 0;
    final controller = AuthController(
      repository,
      LocalCommunityRepository(),
      socialSignOut: () async => socialSignOutCalls += 1,
    );
    await _waitForRestore(controller);

    await controller.logout();

    expect(repository.clearSessionCount, 1);
    expect(socialSignOutCalls, 0);
    expect(controller.state.gateStatus, AuthGateStatus.unauthenticated);
    expect(controller.state.rememberedEmail, 'fake@example.com');
  });
}

Future<void> _waitForRestore(AuthController controller) async {
  await Future<void>.delayed(Duration.zero);
  for (var i = 0; i < 20 && controller.state.isLoading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

MpassSession _session() {
  return MpassSession(
    accessToken: 'fake-token',
    idUser: 'user-1',
    tokenSecExpiration: 3600,
    obtainedAt: DateTime(2026, 8, 2, 11),
  );
}

Trip _trip(String id, DateTime startedAt) {
  return Trip(
    id: id,
    externalId: id,
    userId: 'user-1',
    originStationId: 'A',
    originStationName: 'Origen',
    destinationStationId: 'B',
    destinationStationName: 'Destino',
    startedAt: startedAt,
    durationSeconds: 600,
    isShared: true,
  );
}

class _FakeBicimadRepository implements BicimadRepository {
  _FakeBicimadRepository({required this.session, this.lastAutomaticSyncAt});

  final MpassSession? session;
  DateTime? lastAutomaticSyncAt;
  int fetchCount = 0;
  int clearSessionCount = 0;

  @override
  Future<void> clearSession() async {
    clearSessionCount++;
    lastAutomaticSyncAt = null;
  }

  @override
  Future<void> disconnect() async {
    lastAutomaticSyncAt = null;
  }

  @override
  Future<List<Trip>> fetchTrips(MpassSession session, {int? page}) async {
    fetchCount++;
    return [_trip('fetched-$fetchCount', DateTime(2026, 8, 2, 9))];
  }

  @override
  Future<MpassSession> login({
    required String email,
    required String password,
  }) async {
    return _session();
  }

  @override
  Future<DateTime?> readLastAutomaticSyncAt() async {
    return lastAutomaticSyncAt;
  }

  @override
  Future<String?> readRememberedEmail() async {
    return 'fake@example.com';
  }

  @override
  Future<MpassSession?> restoreSession() async {
    return session;
  }

  @override
  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) async {
    lastAutomaticSyncAt = syncedAt;
  }
}
