import 'dart:async';

import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/authentication/domain/bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:bicimad_social/features/rankings/domain/ranking_service.dart';
import 'package:bicimad_social/features/rankings/domain/route_summary.dart';
import 'package:bicimad_social/features/trips/data/mock_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/community_user.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/domain/trip_history_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncProgress no vuelve a calcular los providers de viajes', () async {
    final repository = _CountingCommunityRepository();
    final recoveredUser = await repository.createOrRecoverUser(
      externalUserId: 'fake-user',
    );
    await repository.updateDisplayName('Fake user');
    final user = recoveredUser.copyWith(displayName: 'Fake user');
    final controller = _ManualAuthController(repository);
    await Future<void>.delayed(Duration.zero);
    controller.authenticate(user);
    expect(controller.state.isAuthenticated, isTrue);
    expect(controller.state.needsDisplayName, isFalse);
    final container = ProviderContainer(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith((ref) => controller),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(myTripsProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(myTripsProvider.future);
    expect(repository.readCount, 1);

    controller.emitProgress(
      const TripHistorySyncProgress(
        pagesFetched: 8,
        tripsProcessed: 240,
        isFullHistoryScan: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(repository.readCount, 1);

    container.read(tripDataRevisionProvider.notifier).state += 1;
    await container.read(myTripsProvider.future);
    expect(repository.readCount, 2);
  });

  test(
    'Rankings solo se invalida cuando cambia la revision de viajes',
    () async {
      final repository = _CountingCommunityRepository();
      final recoveredUser = await repository.createOrRecoverUser(
        externalUserId: 'fake-user',
      );
      await repository.updateDisplayName('Fake user');
      final user = recoveredUser.copyWith(displayName: 'Fake user');
      final controller = _ManualAuthController(repository)..authenticate(user);
      final rankingService = _CountingRankingService();
      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
          authControllerProvider.overrideWith((ref) => controller),
          rankingServiceProvider.overrideWithValue(rankingService),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        routePersonalSummariesProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(routePersonalSummariesProvider.future);
      expect(rankingService.buildCount, 1);

      controller.emitProgress(
        const TripHistorySyncProgress(
          pagesFetched: 3,
          tripsProcessed: 90,
          isFullHistoryScan: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rankingService.buildCount, 1);

      container.read(tripDataRevisionProvider.notifier).state += 1;
      await container.read(routePersonalSummariesProvider.future);
      expect(rankingService.buildCount, 2);
    },
  );
}

class _CountingRankingService extends RankingService {
  int buildCount = 0;

  @override
  List<RouteSummary> buildUserRouteSummaries({
    required Iterable<Trip> myTrips,
    required Iterable<Trip> sharedTrips,
    required String currentUserId,
  }) {
    buildCount += 1;
    return super.buildUserRouteSummaries(
      myTrips: myTrips,
      sharedTrips: sharedTrips,
      currentUserId: currentUserId,
    );
  }
}

class _CountingCommunityRepository extends MockCommunityRepository {
  int readCount = 0;

  @override
  Future<List<Trip>> getMyTrips() {
    readCount += 1;
    return super.getMyTrips();
  }
}

class _ManualAuthController extends AuthController {
  _ManualAuthController(_CountingCommunityRepository repository)
    : super(_NeverRestoringRepository(), repository);

  void authenticate(CommunityUser user) {
    state = AuthState(
      gateStatus: AuthGateStatus.authenticated,
      session: null,
      user: user,
      lastSyncAt: null,
      isLoading: false,
      isSyncing: false,
      syncProgress: null,
      errorMessage: null,
      rememberedEmail: 'fake@example.test',
    );
  }

  void emitProgress(TripHistorySyncProgress progress) {
    state = state.copyWith(isSyncing: true, syncProgress: progress);
  }
}

class _NeverRestoringRepository implements BicimadRepository {
  final Completer<String?> _restoreBlock = Completer<String?>();

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<Trip>> fetchTrips(MpassSession session, {int? page}) async {
    return const [];
  }

  @override
  Future<MpassSession> login({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DateTime?> readLastAutomaticSyncAt() async => null;

  @override
  Future<String?> readRememberedEmail() => _restoreBlock.future;

  @override
  Future<MpassSession?> restoreSession() async => null;

  @override
  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) async {}
}
