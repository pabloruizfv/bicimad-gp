import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/bicimad_build_config.dart';
import '../core/config/supabase_build_config.dart';
import '../core/diagnostics/bicimad_diagnostics.dart';
import '../core/diagnostics/ranking_performance.dart';
import '../core/errors/app_exception.dart';
import '../core/network/http_transport.dart';
import '../core/storage/secure_key_value_store.dart';
import '../features/authentication/data/bicimad_secure_storage.dart';
import '../features/authentication/data/mpass_api_client.dart';
import '../features/authentication/data/real_bicimad_repository.dart';
import '../features/authentication/data/technical_config_resolver.dart';
import '../features/authentication/domain/bicimad_repository.dart';
import '../features/authentication/domain/bicimad_session.dart';
import '../features/achievements/domain/achievement.dart';
import '../features/achievements/domain/achievement_ranking.dart';
import '../features/achievements/domain/achievement_service.dart';
import '../features/general/domain/station_usage.dart';
import '../features/profile/data/avatar_repository.dart';
import '../features/rankings/domain/ranking_service.dart';
import '../features/rankings/domain/community_route_ranking.dart';
import '../features/rankings/domain/head_to_head.dart';
import '../features/rankings/domain/route_key.dart';
import '../features/rankings/domain/route_ranking.dart';
import '../features/rankings/domain/route_summary.dart';
import '../features/social/application/social_auth_controller.dart';
import '../features/social/application/social_trip_sync_service.dart';
import '../features/social/data/social_profile_cache.dart';
import '../features/social/data/supabase_social_repository.dart';
import '../features/social/domain/follow_connection.dart';
import '../features/social/domain/profile_statistics.dart';
import '../features/social/domain/social_profile.dart';
import '../features/social/domain/social_repository.dart';
import '../features/stations/data/station_catalog_repository.dart';
import '../features/trips/data/legacy_route_model_repository.dart';
import '../features/trips/data/local_community_repository.dart';
import '../features/trips/data/personal_trips_database.dart';
import '../features/trips/application/trip_history_sync_service.dart';
import '../features/trips/domain/community_repository.dart';
import '../features/trips/domain/community_user.dart';
import '../features/trips/domain/legacy_route_model.dart';
import '../features/trips/domain/station_code.dart';
import '../features/trips/domain/trip.dart';
import '../features/trips/domain/trip_history_sync.dart';
import '../features/trips/domain/trip_metrics.dart';

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((ref) {
  return const FlutterSecureKeyValueStore();
});

final bicimadBuildConfigProvider = Provider<BicimadBuildConfig>((ref) {
  return BicimadBuildConfig.fromEnvironment();
});

final supabaseBuildConfigProvider = Provider<SupabaseBuildConfig>((ref) {
  return SupabaseBuildConfig.fromEnvironment();
});

final bicimadSecureStorageProvider = Provider<BicimadSecureStorage>((ref) {
  return BicimadSecureStorage(store: ref.watch(secureKeyValueStoreProvider));
});

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  return LocalAvatarRepository(store: ref.watch(secureKeyValueStoreProvider));
});

final selectedAvatarProvider = FutureProvider<String>((ref) {
  final socialAvatar = ref
      .watch(socialAuthControllerProvider)
      .profile
      ?.avatarAsset;
  if (socialAvatar != null) {
    return Future.value(socialAvatar);
  }
  return ref.watch(avatarRepositoryProvider).readSelectedAvatar();
});

final currentDisplayNameProvider = Provider<String?>((ref) {
  final socialDisplayName = ref.watch(
    socialAuthControllerProvider.select(
      (state) => state.profile?.displayName.trim(),
    ),
  );
  if (socialDisplayName != null && socialDisplayName.isNotEmpty) {
    return socialDisplayName;
  }
  final displayName = ref.watch(
    authControllerProvider.select((state) => state.user?.displayName.trim()),
  );
  if (displayName == null || displayName.isEmpty) {
    return null;
  }
  return displayName;
});

final technicalConfigResolverProvider = Provider<TechnicalConfigResolver>((
  ref,
) {
  return TechnicalConfigResolver(
    buildConfig: ref.watch(bicimadBuildConfigProvider),
    secureStorage: ref.watch(bicimadSecureStorageProvider),
  );
});

final httpTransportProvider = Provider<HttpTransport>((ref) {
  final transport = PackageHttpTransport();
  ref.onDispose(transport.close);
  return transport;
});

final mpassApiClientProvider = Provider<MpassApiClient>((ref) {
  return MpassApiClient(transport: ref.watch(httpTransportProvider));
});

final bicimadRepositoryProvider = Provider<BicimadRepository>((ref) {
  return RealBicimadRepository(
    apiClient: ref.watch(mpassApiClientProvider),
    secureStorage: ref.watch(bicimadSecureStorageProvider),
    technicalConfigResolver: ref.watch(technicalConfigResolverProvider),
  );
});

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final database = PersonalTripsDatabase.application();
  ref.onDispose(() => unawaited(database.close()));
  return LocalCommunityRepository(
    store: ref.watch(secureKeyValueStoreProvider),
    database: database,
    stationCatalogRepository: ref.watch(stationCatalogRepositoryProvider),
  );
});

final tripHistorySyncServiceProvider = Provider<TripHistorySyncService>((ref) {
  return TripHistorySyncService(
    bicimadRepository: ref.watch(bicimadRepositoryProvider),
    communityRepository: ref.watch(communityRepositoryProvider),
  );
});

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  final config = ref.watch(supabaseBuildConfigProvider);
  if (!config.isComplete) {
    return const UnavailableSocialRepository();
  }
  return SupabaseSocialRepository(Supabase.instance.client);
});

final socialProfileCacheProvider = Provider<SocialProfileCache>((ref) {
  return SocialProfileCache(store: ref.watch(secureKeyValueStoreProvider));
});

final socialTripSyncServiceProvider = Provider<SocialTripSyncService>((ref) {
  return SocialTripSyncService(
    socialRepository: ref.watch(socialRepositoryProvider),
    localRepository: ref.watch(communityRepositoryProvider),
  );
});

final stationCatalogRepositoryProvider = Provider<StationCatalogRepository>((
  ref,
) {
  return LocalStationCatalogRepository(
    store: ref.watch(secureKeyValueStoreProvider),
    transport: ref.watch(httpTransportProvider),
  );
});

final legacyRouteModelRepositoryProvider = Provider<LegacyRouteModelRepository>(
  (ref) {
    final repository = SqliteLegacyRouteModelRepository();
    ref.onDispose(repository.close);
    return repository;
  },
);

final technicalConfigStatusProvider = FutureProvider<ResolvedTechnicalConfig>((
  ref,
) async {
  return ref.watch(technicalConfigResolverProvider).resolve();
});

final rankingServiceProvider = Provider<RankingService>((ref) {
  return const RankingService();
});

final tripDataRevisionProvider = StateProvider<int>((ref) => 0);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(
      ref.watch(bicimadRepositoryProvider),
      ref.watch(communityRepositoryProvider),
      socialTripSyncService: ref.watch(socialTripSyncServiceProvider),
      tripHistorySyncService: ref.watch(tripHistorySyncServiceProvider),
      socialSignOut: ref.watch(socialRepositoryProvider).signOut,
      socialAccountDeletion: ref
          .watch(socialRepositoryProvider)
          .deleteOwnAccount,
      localPersonalDataDeletion: () async {
        await ref.read(socialProfileCacheProvider).clear();
        await ref.read(avatarRepositoryProvider).clearSelectedAvatar();
        await ref.read(bicimadSecureStorageProvider).clearPersonalData();
      },
      onTripDataChanged: () {
        ref.read(tripDataRevisionProvider.notifier).state += 1;
      },
    );
  },
);

final socialOtpChallengeMemoryProvider = Provider<SocialOtpChallengeMemory>((
  ref,
) {
  return SocialOtpChallengeMemory();
});

final socialAuthControllerProvider =
    StateNotifierProvider<SocialAuthController, SocialAuthState>((ref) {
      final controller = SocialAuthController(
        repository: ref.watch(socialRepositoryProvider),
        cache: ref.watch(socialProfileCacheProvider),
        tripSyncService: ref.watch(socialTripSyncServiceProvider),
        localRepository: ref.watch(communityRepositoryProvider),
        avatarRepository: ref.watch(avatarRepositoryProvider),
        otpChallengeMemory: ref.watch(socialOtpChallengeMemoryProvider),
      );
      ref.listen<AuthState>(authControllerProvider, (previous, next) {
        final session = next.session;
        final email = next.rememberedEmail;
        if (next.isAuthenticated && session != null && email != null) {
          if (controller.isOtpFlowActiveFor(email)) {
            return;
          }
          unawaited(
            controller.bindMpass(
              email: email,
              mpassUserId: session.externalUserId,
            ),
          );
        } else if (previous?.isAuthenticated == true && !next.isAuthenticated) {
          unawaited(controller.resetAfterMpassLogout());
        }
      }, fireImmediately: true);
      return controller;
    });

final currentSocialProfileProvider = Provider<SocialProfile?>((ref) {
  return ref.watch(socialAuthControllerProvider).profile;
});

final achievementServiceProvider = Provider<AchievementService>((ref) {
  return const AchievementService();
});

final ownAchievementProgressProvider = FutureProvider<List<AchievementProgress>>(
  (ref) async {
    final journeys = await ref.watch(myTripsProvider.future);
    final repository = ref.watch(socialRepositoryProvider);
    var persisted = const <UserAchievement>[];
    final userId = repository.currentUserId;
    if (repository.hasSession && userId != null) {
      try {
        persisted = await repository.getUserAchievements(userId);
      } catch (_) {
        // Local progress remains available while the social backend is offline.
      }
    }
    return ref
        .watch(achievementServiceProvider)
        .evaluate(journeys: journeys, persisted: persisted);
  },
);

final profileAchievementSummariesProvider =
    FutureProvider.family<List<AchievementSummary>, String>((
      ref,
      userId,
    ) async {
      final repository = ref.watch(socialRepositoryProvider);
      if (!repository.hasSession) {
        return ref.watch(achievementServiceProvider).summaries(const []);
      }
      final achievements = await repository.getUserAchievements(userId);
      return ref.watch(achievementServiceProvider).summaries(achievements);
    });

final achievementRankingProvider =
    FutureProvider.family<AchievementCommunityRanking, String>((
      ref,
      categoryId,
    ) async {
      final repository = ref.watch(socialRepositoryProvider);
      if (!repository.hasSession) {
        return AchievementCommunityRanking(
          categoryId: categoryId,
          entries: const [],
          totalUsers: 0,
        );
      }
      return repository.getAchievementRanking(categoryId);
    });

final socialSearchProvider = FutureProvider.family<List<SocialProfile>, String>(
  (ref, query) async {
    final normalized = query.trim();
    return ref.watch(socialRepositoryProvider).searchProfiles(normalized);
  },
);

final socialConnectionsProvider =
    FutureProvider.family<List<FollowConnection>, ConnectionListType>((
      ref,
      type,
    ) {
      return ref.watch(socialRepositoryProvider).getConnections(type);
    });

final socialProfileDetailsProvider =
    FutureProvider.family<SocialProfileDetails?, String>((ref, userId) {
      return ref.watch(socialRepositoryProvider).getProfileDetails(userId);
    });

final headToHeadProvider = FutureProvider.family<HeadToHeadSummary, String>((
  ref,
  otherUserId,
) {
  return ref.watch(socialRepositoryProvider).getHeadToHead(otherUserId);
});

final myTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getMyTrips();
});

final myRankingTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getMyRankingTrips();
});

final myTripStagesProvider = FutureProvider<List<Trip>>((ref) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getMyStages();
});

final coverageIntervalsProvider = FutureProvider<List<CoverageInterval>>((
  ref,
) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getCoverageIntervals();
});

final tripHistorySyncStateProvider = FutureProvider<TripHistorySyncState>((
  ref,
) async {
  final isAuthenticated = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
  ref.watch(tripDataRevisionProvider);
  if (!isAuthenticated) {
    return const TripHistorySyncState.initial();
  }
  return ref.watch(communityRepositoryProvider).getTripHistorySyncState();
});

final generalTripMetricsProvider = FutureProvider<GeneralTripMetrics>((
  ref,
) async {
  final trips = await ref.watch(myTripsProvider.future);
  final intervals = await ref.watch(coverageIntervalsProvider.future);
  return GeneralTripMetrics.fromTrips(
    trips: trips,
    coverageIntervals: intervals,
  );
});

final stationUsageProvider = FutureProvider<List<StationUsage>>((ref) async {
  final trips = await ref.watch(myTripsProvider.future);
  if (trips.isEmpty) {
    return const [];
  }
  final catalog = await ref
      .watch(stationCatalogRepositoryProvider)
      .getCatalog();
  return buildStationUsage(trips: trips, catalog: catalog);
});

final stationUsageMapTilesEnabledProvider = Provider<bool>((ref) => true);

final sharedTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getSharedTrips();
});

final communityUsersProvider = FutureProvider<List<CommunityUser>>((ref) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  if (!canReadTrips) {
    return const [];
  }
  return ref.watch(communityRepositoryProvider).getCommunityUsers();
});

final routeRankingProvider = FutureProvider.family<RouteRanking, RouteKey>((
  ref,
  routeKey,
) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
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

final routeTripsProvider = FutureProvider.family<List<Trip>, RouteKey>((
  ref,
  routeKey,
) async {
  final canReadTrips = ref.watch(
    authControllerProvider.select(
      (state) => state.isAuthenticated && !state.needsDisplayName,
    ),
  );
  ref.watch(tripDataRevisionProvider);
  if (!canReadTrips) {
    return const [];
  }
  return ref
      .watch(communityRepositoryProvider)
      .getTripsForRoute(
        originStationId: routeKey.originStationId,
        destinationStationId: routeKey.destinationStationId,
      );
});

final routeCommunityRankingProvider =
    FutureProvider.family<CommunityRouteRanking, RouteKey>((
      ref,
      routeKey,
    ) async {
      ref.watch(tripDataRevisionProvider);
      final repository = ref.watch(socialRepositoryProvider);
      if (!repository.hasSession) {
        return const CommunityRouteRanking(entries: []);
      }
      return repository.getCommunityRouteRanking(
        originStationId: routeKey.originStationId,
        destinationStationId: routeKey.destinationStationId,
      );
    });

final legacyRouteModelProvider =
    FutureProvider.family<LegacyRouteModel?, RouteKey>((ref, routeKey) async {
      final trips = await ref.watch(routeTripsProvider(routeKey).future);
      if (trips.isEmpty) {
        return null;
      }
      final sample = trips.first;
      final originCode = canonicalStationCode(
        stationId: sample.originStationId,
        stationName: sample.originStationName,
      );
      final destinationCode = canonicalStationCode(
        stationId: sample.destinationStationId,
        stationName: sample.destinationStationName,
      );
      if (originCode == null || destinationCode == null) {
        return null;
      }
      return ref
          .watch(legacyRouteModelRepositoryProvider)
          .getRouteModel(
            originStationCode: originCode,
            destinationStationCode: destinationCode,
          );
    });

final routePersonalSummariesProvider = FutureProvider<List<RouteSummary>>((
  ref,
) async {
  final (currentUserId, needsDisplayName) = ref.watch(
    authControllerProvider.select(
      (state) => (state.user?.id, state.needsDisplayName),
    ),
  );
  if (currentUserId == null || needsDisplayName) {
    return const [];
  }

  final myTrips = await ref.watch(myRankingTripsProvider.future);
  final sharedTrips = await ref.watch(sharedTripsProvider.future);
  final stopwatch = Stopwatch()..start();
  final summaries = ref
      .watch(rankingServiceProvider)
      .buildUserRouteSummaries(
        myTrips: myTrips,
        sharedTrips: sharedTrips,
        currentUserId: currentUserId,
      );
  stopwatch.stop();
  logRankingPerformance('build_groups', stopwatch.elapsed);
  return summaries;
});

final routeHistoricalPercentilesProvider =
    FutureProvider<Map<RouteKey, double?>>((ref) async {
      final summaries = await ref.watch(routePersonalSummariesProvider.future);
      if (summaries.isEmpty) {
        return const {};
      }

      final personalToCanonical = <RouteKey, RouteKey>{};
      for (final summary in summaries) {
        final originCode = canonicalStationCode(
          stationId: summary.originStationId,
          stationName: summary.originStationName,
        );
        final destinationCode = canonicalStationCode(
          stationId: summary.destinationStationId,
          stationName: summary.destinationStationName,
        );
        if (originCode == null || destinationCode == null) {
          continue;
        }
        personalToCanonical[RouteKey(
          originStationId: summary.originStationId,
          destinationStationId: summary.destinationStationId,
        )] = RouteKey(
          originStationId: originCode,
          destinationStationId: destinationCode,
        );
      }

      final batchStopwatch = Stopwatch()..start();
      final models = await ref
          .watch(legacyRouteModelRepositoryProvider)
          .getRouteModels(personalToCanonical.values.toSet());
      batchStopwatch.stop();
      logRankingPerformance('batch_models', batchStopwatch.elapsed);

      final summariesByKey = {
        for (final summary in summaries)
          RouteKey(
            originStationId: summary.originStationId,
            destinationStationId: summary.destinationStationId,
          ): summary,
      };
      final calculateStopwatch = Stopwatch()..start();
      final percentiles = <RouteKey, double?>{};
      for (final entry in personalToCanonical.entries) {
        final summary = summariesByKey[entry.key];
        final model = models[entry.value];
        percentiles[entry.key] = summary != null && model?.canPlot == true
            ? model!.percentileForDuration(
                summary.personalBestDurationSeconds.toDouble(),
              )
            : null;
      }
      calculateStopwatch.stop();
      logRankingPerformance(
        'calculate_percentiles',
        calculateStopwatch.elapsed,
      );
      return percentiles;
    });

final routeSummariesProvider = FutureProvider<List<RouteSummary>>((ref) async {
  final summaries = await ref.watch(routePersonalSummariesProvider.future);
  final percentiles = await ref.watch(
    routeHistoricalPercentilesProvider.future,
  );

  return [
    for (final summary in summaries)
      summary.copyWith(
        historicalPercentile:
            percentiles[RouteKey(
              originStationId: summary.originStationId,
              destinationStationId: summary.destinationStationId,
            )],
      ),
  ];
});

class AuthState {
  const AuthState({
    required this.gateStatus,
    required this.session,
    required this.user,
    required this.lastSyncAt,
    required this.isLoading,
    required this.isSyncing,
    required this.syncProgress,
    required this.errorMessage,
    required this.rememberedEmail,
  });

  const AuthState.initial()
    : gateStatus = AuthGateStatus.initializing,
      session = null,
      user = null,
      lastSyncAt = null,
      isLoading = false,
      isSyncing = false,
      syncProgress = null,
      errorMessage = null,
      rememberedEmail = null;

  const AuthState.unauthenticated({this.rememberedEmail, String? error})
    : gateStatus = AuthGateStatus.unauthenticated,
      session = null,
      user = null,
      lastSyncAt = null,
      isLoading = false,
      isSyncing = false,
      syncProgress = null,
      errorMessage = error;

  final AuthGateStatus gateStatus;
  final BicimadSession? session;
  final CommunityUser? user;
  final DateTime? lastSyncAt;
  final bool isLoading;
  final bool isSyncing;
  final TripHistorySyncProgress? syncProgress;
  final String? errorMessage;
  final String? rememberedEmail;

  bool get isAuthenticated => gateStatus == AuthGateStatus.authenticated;

  bool get needsDisplayName {
    final currentUser = user;
    return isAuthenticated &&
        (currentUser == null || currentUser.displayName.trim().isEmpty);
  }

  AuthState copyWith({
    AuthGateStatus? gateStatus,
    BicimadSession? session,
    CommunityUser? user,
    DateTime? lastSyncAt,
    bool? isLoading,
    bool? isSyncing,
    TripHistorySyncProgress? syncProgress,
    String? errorMessage,
    String? rememberedEmail,
    bool clearError = false,
    bool clearSyncProgress = false,
  }) {
    return AuthState(
      gateStatus: gateStatus ?? this.gateStatus,
      session: session ?? this.session,
      user: user ?? this.user,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: clearSyncProgress
          ? null
          : syncProgress ?? this.syncProgress,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      rememberedEmail: rememberedEmail ?? this.rememberedEmail,
    );
  }
}

enum AuthGateStatus {
  initializing,
  authenticated,
  unauthenticated,
  sessionRecoveryError,
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(
    this._bicimadRepository,
    this._communityRepository, {
    SocialTripSyncService? socialTripSyncService,
    TripHistorySyncService? tripHistorySyncService,
    Future<void> Function()? socialSignOut,
    Future<void> Function()? socialAccountDeletion,
    Future<void> Function()? localPersonalDataDeletion,
    void Function()? onTripDataChanged,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       // Public parameter names keep test and provider composition readable.
       // ignore: prefer_initializing_formals
       _socialTripSyncService = socialTripSyncService,
       _tripHistorySyncService =
           tripHistorySyncService ??
           TripHistorySyncService(
             bicimadRepository: _bicimadRepository,
             communityRepository: _communityRepository,
           ),
       // ignore: prefer_initializing_formals
       _socialSignOut = socialSignOut,
       // ignore: prefer_initializing_formals
       _socialAccountDeletion = socialAccountDeletion,
       // ignore: prefer_initializing_formals
       _localPersonalDataDeletion = localPersonalDataDeletion,
       // Public callback name documents the composition boundary in tests.
       // ignore: prefer_initializing_formals
       _onTripDataChanged = onTripDataChanged,
       super(const AuthState.initial()) {
    Future<void>.microtask(restoreSession);
  }

  final BicimadRepository _bicimadRepository;
  final CommunityRepository _communityRepository;
  final SocialTripSyncService? _socialTripSyncService;
  final TripHistorySyncService _tripHistorySyncService;
  final Future<void> Function()? _socialSignOut;
  final Future<void> Function()? _socialAccountDeletion;
  final Future<void> Function()? _localPersonalDataDeletion;
  final void Function()? _onTripDataChanged;
  final DateTime Function() _now;

  Future<void> login({required String email, required String password}) async {
    BicimadDiagnostics.log('auth', 'submit_started');
    state = state.copyWith(isLoading: true, clearError: true);
    BicimadSession? session;
    CommunityUser? user;
    try {
      session = await _bicimadRepository.login(
        email: email,
        password: password,
      );
      user = await _communityRepository.createOrRecoverUser(
        externalUserId: session.externalUserId,
      );
      state = AuthState(
        gateStatus: AuthGateStatus.authenticated,
        session: session,
        user: user,
        lastSyncAt: null,
        isLoading: false,
        isSyncing: true,
        syncProgress: null,
        errorMessage: null,
        rememberedEmail: email,
      );
      await _trySocialPull(email: email, session: session);
      await _runTripHistorySync(session: session, email: email);
      await _trySocialPush(email: email);
      final syncedAt = _now();
      await _bicimadRepository.saveLastAutomaticSyncAt(syncedAt);
      state = AuthState(
        gateStatus: AuthGateStatus.authenticated,
        session: session,
        user: state.user ?? user,
        lastSyncAt: syncedAt,
        isLoading: false,
        isSyncing: false,
        syncProgress: null,
        errorMessage: null,
        rememberedEmail: email,
      );
    } catch (error) {
      BicimadDiagnostics.error('auth', error);
      if (session != null && user != null) {
        state = state.copyWith(
          gateStatus: AuthGateStatus.authenticated,
          session: session,
          user: state.user ?? user,
          isLoading: false,
          isSyncing: false,
          clearSyncProgress: true,
          errorMessage: _safeErrorMessage(error),
          rememberedEmail: email,
        );
      } else {
        state = state.copyWith(
          gateStatus: AuthGateStatus.unauthenticated,
          isLoading: false,
          isSyncing: false,
          clearSyncProgress: true,
          errorMessage: _safeErrorMessage(error),
          rememberedEmail: email,
        );
      }
    }
  }

  Future<void> restoreSession() async {
    state = state.copyWith(
      gateStatus: AuthGateStatus.initializing,
      isLoading: false,
      clearError: true,
    );
    BicimadSession? session;
    CommunityUser? user;
    DateTime? lastSyncAt;
    try {
      final rememberedEmail = await _bicimadRepository.readRememberedEmail();
      session = await _bicimadRepository.restoreSession();
      if (session == null) {
        state = AuthState.unauthenticated(rememberedEmail: rememberedEmail);
        return;
      }
      user = await _communityRepository.createOrRecoverUser(
        externalUserId: session.externalUserId,
      );
      final lastAutomaticSyncAt = await _bicimadRepository
          .readLastAutomaticSyncAt();
      final currentTrips = await _communityRepository.getMyTrips();
      final shouldSync =
          currentTrips.isEmpty || _shouldRunHourlySync(lastAutomaticSyncAt);
      lastSyncAt = lastAutomaticSyncAt;

      if (shouldSync) {
        state = state.copyWith(isSyncing: true, clearSyncProgress: true);
        if (rememberedEmail != null) {
          await _trySocialPull(email: rememberedEmail, session: session);
        }
        await _runTripHistorySync(session: session, email: rememberedEmail);
        if (rememberedEmail != null) {
          await _trySocialPush(email: rememberedEmail);
        }
        lastSyncAt = _now();
        await _bicimadRepository.saveLastAutomaticSyncAt(lastSyncAt);
      }
      state = AuthState(
        gateStatus: AuthGateStatus.authenticated,
        session: session,
        user: user,
        lastSyncAt: lastSyncAt,
        isLoading: false,
        isSyncing: false,
        syncProgress: null,
        errorMessage: null,
        rememberedEmail: rememberedEmail,
      );
    } on SessionExpiredException catch (error) {
      BicimadDiagnostics.error('session', error);
      await _communityRepository.clear();
      final rememberedEmail = await _bicimadRepository.readRememberedEmail();
      state = AuthState.unauthenticated(rememberedEmail: rememberedEmail);
    } on NetworkException catch (error) {
      BicimadDiagnostics.error('session', error);
      state = AuthState(
        gateStatus: AuthGateStatus.sessionRecoveryError,
        session: session,
        user: user,
        lastSyncAt: lastSyncAt,
        isLoading: false,
        isSyncing: false,
        syncProgress: null,
        errorMessage: 'No se ha podido conectar para recuperar tu sesión.',
        rememberedEmail: await _bicimadRepository.readRememberedEmail(),
      );
    } catch (error) {
      if (session != null && user != null) {
        state = AuthState(
          gateStatus: AuthGateStatus.authenticated,
          session: session,
          user: user,
          lastSyncAt: lastSyncAt,
          isLoading: false,
          isSyncing: false,
          syncProgress: null,
          errorMessage: _safeErrorMessage(error),
          rememberedEmail: await _bicimadRepository.readRememberedEmail(),
        );
      } else {
        await _communityRepository.clear();
        state = AuthState.unauthenticated(
          rememberedEmail: await _bicimadRepository.readRememberedEmail(),
          error: _safeErrorMessage(error),
        );
      }
    }
  }

  Future<void> retrySessionRecovery() {
    return restoreSession();
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
    if (session == null || state.isSyncing) {
      return;
    }
    state = state.copyWith(
      isSyncing: true,
      clearError: true,
      clearSyncProgress: true,
    );
    try {
      final email = state.rememberedEmail;
      await _runTripHistorySync(session: session, email: email);
      if (email != null) {
        await _trySocialSync(email: email, session: session);
      }
      final syncedAt = _now();
      await _bicimadRepository.saveLastAutomaticSyncAt(syncedAt);
      state = state.copyWith(
        lastSyncAt: syncedAt,
        isSyncing: false,
        clearSyncProgress: true,
        clearError: true,
      );
    } catch (error) {
      if (error is SessionExpiredException) {
        await _bicimadRepository.clearSession();
        await _communityRepository.clear();
        state = AuthState(
          gateStatus: AuthGateStatus.unauthenticated,
          session: null,
          user: null,
          lastSyncAt: null,
          isLoading: false,
          isSyncing: false,
          syncProgress: null,
          errorMessage: _safeErrorMessage(error),
          rememberedEmail: state.rememberedEmail,
        );
        return;
      }
      state = state.copyWith(
        isSyncing: false,
        clearSyncProgress: true,
        errorMessage: _safeErrorMessage(error),
      );
    }
  }

  Future<void> disconnect() async {
    await _signOutSocialBestEffort();
    await _bicimadRepository.disconnect();
    await _communityRepository.clear();
    state = AuthState.unauthenticated(rememberedEmail: state.rememberedEmail);
  }

  Future<void> logout() async {
    // Keep the device's Supabase refresh session so the same MPass account can
    // return without requesting another OTP. A different MPass email is still
    // rejected and signs out the social session in SocialAuthController.
    await _bicimadRepository.clearSession();
    await _communityRepository.clear();
    state = AuthState.unauthenticated(rememberedEmail: state.rememberedEmail);
  }

  Future<bool> deleteMyAccount() async {
    if (state.isLoading || state.isSyncing) {
      return false;
    }
    final deleteSocialAccount = _socialAccountDeletion;
    if (deleteSocialAccount == null) {
      state = state.copyWith(
        errorMessage: 'No se ha podido eliminar tu cuenta.',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await deleteSocialAccount();
      await _communityRepository.deleteMyData();
      final deleteLocalPersonalData = _localPersonalDataDeletion;
      if (deleteLocalPersonalData != null) {
        await deleteLocalPersonalData();
      } else {
        await _bicimadRepository.clearSession();
      }
      _onTripDataChanged?.call();
      state = const AuthState.unauthenticated();
      return true;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No se ha podido eliminar tu cuenta.',
      );
      return false;
    }
  }

  Future<void> _signOutSocialBestEffort() async {
    try {
      await _socialSignOut?.call();
    } catch (_) {
      // MPass and local data must still be cleared if social sign-out fails.
    }
  }

  String _safeErrorMessage(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return 'Ha ocurrido un error recuperable.';
  }

  bool _shouldRunHourlySync(DateTime? lastSyncAt) {
    if (lastSyncAt == null) {
      return true;
    }
    return _now().difference(lastSyncAt) > const Duration(hours: 1);
  }

  Future<void> _runTripHistorySync({
    required BicimadSession session,
    required String? email,
  }) async {
    try {
      await _tripHistorySyncService.synchronize(
        session,
        onProgress: (progress) {
          state = state.copyWith(isSyncing: true, syncProgress: progress);
        },
        onPagePersisted: email == null
            ? null
            : (trips) => _trySocialPushBatch(email: email, trips: trips),
      );
    } finally {
      _onTripDataChanged?.call();
    }
  }

  Future<void> _trySocialSync({
    required String email,
    required BicimadSession session,
  }) async {
    final service = _socialTripSyncService;
    final normalizedEmail = normalizeEmail(email);
    if (service == null || normalizedEmail == null) {
      return;
    }
    try {
      await service.synchronize(
        normalizedMpassEmail: normalizedEmail,
        mpassUserId: session.externalUserId,
      );
    } on SocialIdentityMismatchException {
      // The social controller will request OTP for the active MPass email.
    } catch (_) {
      // Local BiciMAD synchronization remains available while Supabase is offline.
    }
  }

  Future<void> _trySocialPull({
    required String email,
    required BicimadSession session,
  }) async {
    final service = _socialTripSyncService;
    final normalizedEmail = normalizeEmail(email);
    if (service == null || normalizedEmail == null) {
      return;
    }
    try {
      await service.pullCloudHistory(
        normalizedMpassEmail: normalizedEmail,
        mpassUserId: session.externalUserId,
      );
    } on SocialIdentityMismatchException {
      // The social controller will request OTP for the active MPass email.
    } catch (_) {
      // Local BiciMAD synchronization remains available while Supabase is offline.
    }
  }

  Future<void> _trySocialPush({required String email}) async {
    final service = _socialTripSyncService;
    final normalizedEmail = normalizeEmail(email);
    if (service == null || normalizedEmail == null) {
      return;
    }
    try {
      await service.pushLocalHistory(normalizedMpassEmail: normalizedEmail);
    } on SocialIdentityMismatchException {
      // The social controller will request OTP for the active MPass email.
    } catch (_) {
      // Local BiciMAD synchronization remains available while Supabase is offline.
    }
  }

  Future<void> _trySocialPushBatch({
    required String email,
    required List<Trip> trips,
  }) async {
    final service = _socialTripSyncService;
    final normalizedEmail = normalizeEmail(email);
    if (service == null || normalizedEmail == null) {
      return;
    }
    try {
      await service.pushTripBatch(
        normalizedMpassEmail: normalizedEmail,
        trips: trips,
      );
    } on SocialIdentityMismatchException {
      // The social controller will request OTP for the active MPass email.
    } catch (_) {
      // Each page remains persisted locally while Supabase is offline.
    }
  }
}
