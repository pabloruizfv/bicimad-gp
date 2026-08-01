import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/authentication/data/mock_bicimad_repository.dart';
import '../features/authentication/domain/bicimad_repository.dart';
import '../features/authentication/domain/bicimad_session.dart';
import '../features/rankings/domain/ranking_service.dart';
import '../features/rankings/domain/route_key.dart';
import '../features/rankings/domain/route_ranking.dart';
import '../features/rankings/domain/route_summary.dart';
import '../features/trips/data/mock_community_repository.dart';
import '../features/trips/domain/community_repository.dart';
import '../features/trips/domain/community_user.dart';
import '../features/trips/domain/trip.dart';

final bicimadRepositoryProvider = Provider<BicimadRepository>((ref) {
  return MockBicimadRepository();
});

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return MockCommunityRepository();
});

final rankingServiceProvider = Provider<RankingService>((ref) {
  return const RankingService();
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(
      ref.watch(bicimadRepositoryProvider),
      ref.watch(communityRepositoryProvider),
    );
  },
);

final myTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final authState = ref.watch(authControllerProvider);
  if (!authState.isAuthenticated || authState.needsDisplayName) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getMyTrips();
});

final sharedTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final authState = ref.watch(authControllerProvider);
  if (!authState.isAuthenticated || authState.needsDisplayName) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getSharedTrips();
});

final communityUsersProvider = FutureProvider<List<CommunityUser>>((ref) async {
  final authState = ref.watch(authControllerProvider);
  if (!authState.isAuthenticated || authState.needsDisplayName) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getCommunityUsers();
});

final routeRankingProvider = FutureProvider.family<RouteRanking, RouteKey>((
  ref,
  routeKey,
) async {
  final authState = ref.watch(authControllerProvider);
  if (!authState.isAuthenticated || authState.needsDisplayName) {
    throw StateError('No hay una sesion activa.');
  }
  return ref
      .watch(communityRepositoryProvider)
      .getRouteRanking(
        originStationId: routeKey.originStationId,
        destinationStationId: routeKey.destinationStationId,
      );
});

final tripByIdProvider = FutureProvider.family<Trip?, String>((
  ref,
  tripId,
) async {
  final trips = await ref.watch(myTripsProvider.future);
  for (final trip in trips) {
    if (trip.id == tripId) {
      return trip;
    }
  }
  return null;
});

final routeSummariesProvider = FutureProvider<List<RouteSummary>>((ref) async {
  final authState = ref.watch(authControllerProvider);
  final currentUser = authState.user;
  if (currentUser == null || authState.needsDisplayName) {
    return const [];
  }

  final myTrips = await ref.watch(myTripsProvider.future);
  final sharedTrips = await ref.watch(sharedTripsProvider.future);
  final users = await ref.watch(communityUsersProvider.future);

  return ref
      .watch(rankingServiceProvider)
      .buildUserRouteSummaries(
        myTrips: myTrips,
        sharedTrips: sharedTrips,
        users: users,
        currentUserId: currentUser.id,
      );
});

class AuthState {
  const AuthState({
    required this.session,
    required this.user,
    required this.lastSyncAt,
    required this.isLoading,
    required this.isSyncing,
    required this.errorMessage,
  });

  const AuthState.initial()
    : session = null,
      user = null,
      lastSyncAt = null,
      isLoading = false,
      isSyncing = false,
      errorMessage = null;

  final BicimadSession? session;
  final CommunityUser? user;
  final DateTime? lastSyncAt;
  final bool isLoading;
  final bool isSyncing;
  final String? errorMessage;

  bool get isAuthenticated => session != null;

  bool get needsDisplayName {
    final currentUser = user;
    return session != null &&
        (currentUser == null || currentUser.displayName.trim().isEmpty);
  }

  AuthState copyWith({
    BicimadSession? session,
    CommunityUser? user,
    DateTime? lastSyncAt,
    bool? isLoading,
    bool? isSyncing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      session: session ?? this.session,
      user: user ?? this.user,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._bicimadRepository, this._communityRepository)
    : super(const AuthState.initial());

  final BicimadRepository _bicimadRepository;
  final CommunityRepository _communityRepository;

  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final session = await _bicimadRepository.login(
        username: username,
        password: password,
      );
      final user = await _communityRepository.createOrRecoverUser(
        externalUserId: session.externalUserId,
      );
      await _bicimadRepository.fetchTrips(session);
      state = AuthState(
        session: session,
        user: user,
        lastSyncAt: DateTime.now(),
        isLoading: false,
        isSyncing: false,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<void> completeDisplayName(String displayName) async {
    final currentUser = state.user;
    if (currentUser == null) {
      return;
    }
    final trimmedName = displayName.trim();
    await _communityRepository.updateDisplayName(trimmedName);
    state = state.copyWith(
      user: currentUser.copyWith(displayName: trimmedName),
      clearError: true,
    );
  }

  Future<void> synchronizeTrips() async {
    final session = state.session;
    if (session == null) {
      return;
    }
    state = state.copyWith(isSyncing: true, clearError: true);
    await _bicimadRepository.fetchTrips(session);
    state = state.copyWith(
      lastSyncAt: DateTime.now(),
      isSyncing: false,
      clearError: true,
    );
  }

  Future<void> disconnect() async {
    await _bicimadRepository.disconnect();
    state = const AuthState.initial();
  }

  Future<void> logout() async {
    state = const AuthState.initial();
  }
}
