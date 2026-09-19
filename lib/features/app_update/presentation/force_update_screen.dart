import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/app_update.dart';

class ForceUpdateScreen extends ConsumerWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final downloading = state.status == AppUpdateStatus.downloading;
    final progress = state.progress;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_alt, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Actualización necesaria',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Esta versión ya no es compatible con los servicios actuales. Descarga la última versión para continuar.',
                  textAlign: TextAlign.center,
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'No se ha podido completar la actualización. Revisa la conexión e inténtalo de nuevo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (downloading && progress != null) ...[
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).round()}%'),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: downloading
                      ? null
                      : () => ref
                            .read(appUpdateControllerProvider.notifier)
                            .downloadAndInstall(),
                  icon: const Icon(Icons.download),
                  label: Text(
                    downloading ? 'Descargando…' : 'Actualizar ahora',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
