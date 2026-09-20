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
    final installing = state.status == AppUpdateStatus.installing;
    final awaitingPermission =
        state.status == AppUpdateStatus.awaitingPermission;
    final ready = state.status == AppUpdateStatus.ready;
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
                if (downloading) ...[
                  const Text('Descargando actualización...'),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 10),
                  if (progress != null) Text('${(progress * 100).round()}%'),
                  const SizedBox(height: 12),
                ],
                if (awaitingPermission)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Activa el permiso para esta app en Android y vuelve aquí.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (ready)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Descarga completa. Confirma la instalación en Android.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                FilledButton.icon(
                  onPressed: downloading || installing
                      ? null
                      : () {
                          final controller = ref.read(
                            appUpdateControllerProvider.notifier,
                          );
                          if (ready || awaitingPermission) {
                            controller.installDownloaded();
                          } else {
                            controller.downloadAndInstall();
                          }
                        },
                  icon: const Icon(Icons.download),
                  label: Text(
                    downloading
                        ? 'Descargando...'
                        : installing
                        ? 'Abriendo...'
                        : awaitingPermission
                        ? 'Abrir permisos'
                        : ready
                        ? 'Instalar'
                        : 'Actualizar ahora',
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
