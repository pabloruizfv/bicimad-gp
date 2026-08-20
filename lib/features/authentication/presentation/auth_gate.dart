import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../social/presentation/social_auth_gate.dart';
import '../../trips/domain/trip_history_sync.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return switch (authState.gateStatus) {
      AuthGateStatus.initializing => _InitializingSessionView(
        progress: authState.syncProgress,
      ),
      AuthGateStatus.sessionRecoveryError => const _SessionRecoveryErrorView(),
      AuthGateStatus.authenticated => const SocialAuthGate(),
      AuthGateStatus.unauthenticated => const _InitializingSessionView(),
    };
  }
}

class _InitializingSessionView extends StatelessWidget {
  const _InitializingSessionView({this.progress});

  final TripHistorySyncProgress? progress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              if (progress != null)
                Text('Recuperando viajes...')
              else
                Text('Preparando la aplicación…'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionRecoveryErrorView extends ConsumerWidget {
  const _SessionRecoveryErrorView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'No se ha podido recuperar tu sesión',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    authState.errorMessage ??
                        'Revisa la conexión y vuelve a intentarlo.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(authControllerProvider.notifier)
                        .retrySessionRecovery(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
