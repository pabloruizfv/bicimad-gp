import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/authentication/presentation/display_name_screen.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/rankings/domain/route_key.dart';
import '../features/rankings/presentation/ranking_detail_screen.dart';
import '../features/rankings/presentation/rankings_screen.dart';
import '../features/trips/presentation/trip_detail_screen.dart';
import '../features/trips/presentation/trips_screen.dart';
import 'providers.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/trips',
    redirect: (context, state) {
      final location = state.uri.path;
      final isLogin = location == '/login';
      final isDisplayName = location == '/display-name';

      if (!authState.isAuthenticated) {
        return isLogin ? null : '/login';
      }

      if (authState.needsDisplayName) {
        return isDisplayName ? null : '/display-name';
      }

      if (isLogin || isDisplayName || location == '/') {
        return '/trips';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/display-name',
        builder: (context, state) => const DisplayNameScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return MainScaffold(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: '/trips',
            builder: (context, state) => const TripsScreen(),
          ),
          GoRoute(
            path: '/rankings',
            builder: (context, state) => const RankingsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
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
              context.go('/trips');
              break;
            case 1:
              context.go('/rankings');
              break;
            case 2:
              context.go('/profile');
              break;
          }
        },
        destinations: const [
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  int _selectedIndex(String location) {
    if (location.startsWith('/rankings')) {
      return 1;
    }
    if (location.startsWith('/profile')) {
      return 2;
    }
    return 0;
  }
}
