import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_identity.dart';
import '../features/app_update/domain/app_update.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class BicimadSocialApp extends ConsumerStatefulWidget {
  const BicimadSocialApp({super.key});

  @override
  ConsumerState<BicimadSocialApp> createState() => _BicimadSocialAppState();
}

class _BicimadSocialAppState extends ConsumerState<BicimadSocialApp> {
  bool _optionalUpdatePromptShown = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUpdateState>(appUpdateControllerProvider, (previous, next) {
      if (next.status != AppUpdateStatus.available ||
          _optionalUpdatePromptShown) {
        return;
      }
      _optionalUpdatePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (_) => const OptionalUpdateDialog(),
        );
      });
    });
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: appDisplayName,
      theme: buildAppTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class OptionalUpdateDialog extends ConsumerWidget {
  const OptionalUpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final info = state.info;
    final downloading = state.status == AppUpdateStatus.downloading;
    final progress = state.progress;
    return AlertDialog(
      title: const Text('Nueva versión disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info == null
                ? 'Puedes actualizar BiciMAD GP.'
                : 'La versión ${info.latestVersion} está disponible.',
          ),
          if (downloading && progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('${(progress * 100).round()}%'),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              'No se ha podido descargar la actualización. Revisa la conexión e inténtalo de nuevo.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (!downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ahora no'),
          ),
        FilledButton.icon(
          onPressed: downloading
              ? null
              : () => ref
                    .read(appUpdateControllerProvider.notifier)
                    .downloadAndInstall(),
          icon: const Icon(Icons.download),
          label: Text(downloading ? 'Descargando…' : 'Actualizar'),
        ),
      ],
    );
  }
}
