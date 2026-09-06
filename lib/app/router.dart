import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/authentication/presentation/auth_gate.dart';
import '../features/authentication/presentation/display_name_screen.dart';
import '../features/authentication/presentation/experimental_config_screen.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/general/presentation/general_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/rankings/domain/route_key.dart';
import '../features/rankings/presentation/ranking_detail_screen.dart';
import '../features/rankings/presentation/rankings_screen.dart';
import '../features/rankings/presentation/head_to_head_screen.dart';
import '../features/social/application/social_auth_controller.dart';
import '../features/social/presentation/community_screen.dart';
import '../features/social/presentation/social_onboarding_screen.dart';
import '../features/social/presentation/social_otp_screen.dart';
import '../features/social/presentation/social_profile_screen.dart';
import '../features/trips/presentation/route_history_screen.dart';
import '../features/trips/presentation/trip_detail_screen.dart';
import '../features/trips/presentation/trips_screen.dart';
import 'providers.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final (authGateStatus, needsDisplayName) = ref.watch(
    authControllerProvider.select(
      (state) => (state.gateStatus, state.needsDisplayName),
    ),
  );
  final socialStatus = ref.watch(
    socialAuthControllerProvider.select((state) => state.status),
  );

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) => resolveAppRedirect(
      location: state.uri.path,
      authGateStatus: authGateStatus,
      needsDisplayName: needsDisplayName,
      socialStatus: socialStatus,
    ),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGate()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/display-name',
        builder: (context, state) => const DisplayNameScreen(),
      ),
      GoRoute(
        path: '/experimental-config',
        builder: (context, state) => const ExperimentalConfigScreen(),
      ),
      GoRoute(
        path: '/social-otp',
        builder: (context, state) => const SocialOtpScreen(),
      ),
      GoRoute(
        path: '/social-onboarding',
        builder: (context, state) => const SocialOnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return MainScaffold(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: '/general',
            builder: (context, state) => const GeneralScreen(),
          ),
          GoRoute(
            path: '/trips',
            builder: (context, state) => const TripsScreen(),
          ),
          GoRoute(
            path: '/rankings',
            builder: (context, state) => const RankingsScreen(),
          ),
          GoRoute(
            path: '/community',
            builder: (context, state) {
              final initialTab = switch (state.uri.queryParameters['tab']) {
                'followers' => CommunityTab.followers,
                'following' => CommunityTab.following,
                'requests' => CommunityTab.requests,
                _ => CommunityTab.search,
              };
              return CommunityScreen(
                key: ValueKey('community-${initialTab.name}'),
                initialTab: initialTab,
              );
            },
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/social-profile/:userId',
        builder: (context, state) {
          return SocialProfileScreen(userId: state.pathParameters['userId']!);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/head-to-head/:otherUserId',
        builder: (context, state) =>
            HeadToHeadScreen(otherUserId: state.pathParameters['otherUserId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/trip/:tripId',
        builder: (context, state) {
          return TripDetailScreen(tripId: state.pathParameters['tripId']!);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/route-history/:originStationId/:destinationStationId',
        builder: (context, state) {
          final isRankingsView =
              state.uri.queryParameters['view'] == 'rankings';
          return RouteHistoryScreen(
            routeKey: RouteKey(
              originStationId: state.pathParameters['originStationId']!,
              destinationStationId:
                  state.pathParameters['destinationStationId']!,
            ),
            selectedTripId: state.uri.queryParameters['selectedTripId'],
            showOverview: !isRankingsView,
            allowTripNavigation: isRankingsView,
            startInCommunity: state.uri.queryParameters['mode'] == 'community',
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/ranking/:originStationId/:destinationStationId',
        builder: (context, state) {
          return RankingDetailScreen(
            routeKey: RouteKey(
              originStationId: state.pathParameters['originStationId']!,
              destinationStationId:
                  state.pathParameters['destinationStationId']!,
            ),
          );
        },
      ),
    ],
  );
});

String? resolveAppRedirect({
  required String location,
  required AuthGateStatus authGateStatus,
  required bool needsDisplayName,
  required SocialAuthStatus socialStatus,
}) {
  final isRoot = location == '/';
  final isLogin = location == '/login';
  final isDisplayName = location == '/display-name';
  final isExperimentalConfig = location == '/experimental-config';
  final isSocialOtp = location == '/social-otp';
  final isSocialOnboarding = location == '/social-onboarding';
  final hasPendingOtp =
      socialStatus == SocialAuthStatus.otpPending ||
      socialStatus == SocialAuthStatus.verifyingOtp;

  if (hasPendingOtp && authGateStatus != AuthGateStatus.unauthenticated) {
    return isSocialOtp ? null : '/social-otp';
  }

  if (authGateStatus == AuthGateStatus.initializing ||
      authGateStatus == AuthGateStatus.sessionRecoveryError) {
    if (isRoot || isExperimentalConfig) {
      return null;
    }
    return '/';
  }

  if (authGateStatus == AuthGateStatus.unauthenticated) {
    if (isExperimentalConfig) {
      return null;
    }
    return isLogin ? null : '/login';
  }

  if (needsDisplayName) {
    return isDisplayName ? null : '/display-name';
  }

  return switch (socialStatus) {
    SocialAuthStatus.otpPending ||
    SocialAuthStatus.verifyingOtp => isSocialOtp ? null : '/social-otp',
    SocialAuthStatus.needsProfile =>
      isSocialOnboarding ? null : '/social-onboarding',
    SocialAuthStatus.ready =>
      isLogin || isDisplayName || isRoot || isSocialOtp || isSocialOnboarding
          ? '/general'
          : null,
    SocialAuthStatus.waitingForMpass ||
    SocialAuthStatus.initializing ||
    SocialAuthStatus.sendingOtp ||
    SocialAuthStatus.error => isRoot ? null : '/',
  };
}

class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(location),
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/general');
              break;
            case 1:
              context.go('/trips');
              break;
            case 2:
              context.go('/rankings');
              break;
            case 3:
              context.go('/community');
              break;
            case 4:
              context.go('/profile');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Mi Perfil',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bike_outlined),
            selectedIcon: Icon(Icons.directions_bike),
            label: 'Viajes',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Rankings',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Comunidad',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  int _selectedIndex(String location) {
    if (location.startsWith('/trips')) {
      return 1;
    }
    if (location.startsWith('/rankings')) {
      return 2;
    }
    if (location.startsWith('/profile')) {
      return 4;
    }
    if (location.startsWith('/community')) {
      return 3;
    }
    return 0;
  }
}
