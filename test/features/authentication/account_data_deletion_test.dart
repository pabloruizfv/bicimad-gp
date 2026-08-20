import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/authentication/data/mock_bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/domain/bicimad_session.dart';
import 'package:bicimad_social/features/trips/data/local_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/community_user.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'elimina primero la cuenta social y despues los datos locales',
    () async {
      final local = LocalCommunityRepository();
      await local.createOrRecoverUser(externalUserId: 'user-1');
      await local.replaceMyTrips([_trip()]);
      final operations = <String>[];
      final controller = _DeletionAuthController(
        local,
        socialAccountDeletion: () async => operations.add('social'),
        localPersonalDataDeletion: () async => operations.add('local_secure'),
      )..authenticate();

      expect(await controller.deleteMyAccount(), isTrue);

      expect(operations, ['social', 'local_secure']);
      await local.createOrRecoverUser(externalUserId: 'user-1');
      expect(await local.getMyTrips(), isEmpty);
      expect(controller.state.gateStatus, AuthGateStatus.unauthenticated);
      expect(controller.state.rememberedEmail, isNull);
    },
  );

  test('si Supabase falla conserva los viajes locales', () async {
    final local = LocalCommunityRepository();
    await local.createOrRecoverUser(externalUserId: 'user-1');
    await local.replaceMyTrips([_trip()]);
    var localCleanupCalls = 0;
    final controller = _DeletionAuthController(
      local,
      socialAccountDeletion: () async => throw StateError('remote failure'),
      localPersonalDataDeletion: () async => localCleanupCalls += 1,
    )..authenticate();

    expect(await controller.deleteMyAccount(), isFalse);

    expect(localCleanupCalls, 0);
    expect(await local.getMyTrips(), hasLength(1));
    expect(controller.state.isAuthenticated, isTrue);
    expect(
      controller.state.errorMessage,
      'No se ha podido eliminar tu cuenta.',
    );
  });
}

class _DeletionAuthController extends AuthController {
  _DeletionAuthController(
    LocalCommunityRepository repository, {
    required Future<void> Function() socialAccountDeletion,
    required Future<void> Function() localPersonalDataDeletion,
  }) : super(
         MockBicimadRepository(),
         repository,
         socialAccountDeletion: socialAccountDeletion,
         localPersonalDataDeletion: localPersonalDataDeletion,
       );

  @override
  Future<void> restoreSession() async {}

  void authenticate() {
    state = AuthState(
      gateStatus: AuthGateStatus.authenticated,
      session: BicimadSession(
        accessToken: 'fake-token',
        idUser: 'user-1',
        tokenSecExpiration: 3600,
        obtainedAt: DateTime(2026, 8, 7),
      ),
      user: CommunityUser(
        id: 'user-1',
        externalUserId: 'user-1',
        displayName: 'Test',
        createdAt: DateTime(2026, 8, 7),
      ),
      lastSyncAt: null,
      isLoading: false,
      isSyncing: false,
      syncProgress: null,
      errorMessage: null,
      rememberedEmail: 'test@example.test',
    );
  }
}

Trip _trip() {
  return Trip(
    id: 'trip-1',
    externalId: 'trip-1',
    userId: 'user-1',
    originStationId: '1',
    originStationName: '1 - Origin',
    destinationStationId: '2',
    destinationStationName: '2 - Destination',
    startedAt: DateTime(2026, 8, 7),
    durationSeconds: 600,
    isShared: true,
  );
}
