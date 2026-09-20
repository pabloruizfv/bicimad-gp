import 'dart:async';

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

class _BicimadSocialAppState extends ConsumerState<BicimadSocialApp>
    with WidgetsBindingObserver {
  bool _optionalUpdatePromptShown = false;
  bool _optionalUpdatePromptScheduled = false;
  String? _deferredUpdateVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(appUpdateControllerProvider.notifier).onResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUpdateState>(appUpdateControllerProvider, (previous, next) {
      _showOptionalUpdateIfAvailable(next);
    });
    final updateState = ref.watch(appUpdateControllerProvider);
    _showOptionalUpdateIfAvailable(updateState);
    final router = ref.watch(routerProvider);
    final showUpdateOverlay =
        _optionalUpdatePromptShown &&
        !updateState.isRequired &&
        (updateState.status == AppUpdateStatus.available ||
            updateState.status == AppUpdateStatus.downloading ||
            updateState.status == AppUpdateStatus.awaitingPermission ||
            updateState.status == AppUpdateStatus.installing ||
            updateState.status == AppUpdateStatus.ready);

    return MaterialApp.router(
      title: appDisplayName,
      theme: buildAppTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          if (showUpdateOverlay) ...[
            const ModalBarrier(color: Color(0x99000000), dismissible: false),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: OptionalUpdateDialog(
                  onDismiss: () => setState(() {
                    _optionalUpdatePromptShown = false;
                    _deferredUpdateVersion = updateState.info?.latestVersion;
                  }),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showOptionalUpdateIfAvailable(AppUpdateState state) {
    if ((state.status != AppUpdateStatus.available &&
            state.status != AppUpdateStatus.downloading) ||
        (state.status == AppUpdateStatus.available &&
            state.info?.latestVersion == _deferredUpdateVersion) ||
        _optionalUpdatePromptShown ||
        _optionalUpdatePromptScheduled) {
      return;
    }
    _optionalUpdatePromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _optionalUpdatePromptScheduled = false;
      if (!mounted) return;
      setState(() => _optionalUpdatePromptShown = true);
    });
  }
}

class OptionalUpdateDialog extends ConsumerWidget {
  const OptionalUpdateDialog({this.onDismiss, super.key});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final info = state.info;
    final downloading = state.status == AppUpdateStatus.downloading;
    final installing = state.status == AppUpdateStatus.installing;
    final awaitingPermission =
        state.status == AppUpdateStatus.awaitingPermission;
    final ready = state.status == AppUpdateStatus.ready;
    final progress = state.progress;
    return PopScope(
      canPop: !downloading && !installing,
      child: AlertDialog(
        title: Text(
          downloading
              ? 'Descargando actualización...'
              : installing
              ? 'Abriendo el instalador...'
              : awaitingPermission
              ? 'Permite instalar la actualización'
              : ready
              ? 'Actualización descargada'
              : 'Nueva versión disponible',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info == null
                  ? 'Puedes actualizar BiciMAD GP.'
                  : 'La versión ${info.latestVersion} está disponible.',
            ),
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              if (progress != null) Text('${(progress * 100).round()}%'),
            ],
            if (awaitingPermission)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Activa el permiso para esta app en Android y vuelve aquí.',
                ),
              ),
            if (ready)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Pulsa Instalar y confirma la actualización en Android.',
                ),
              ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                state.errorMessage!.contains('INVALID_APK')
                    ? 'El APK descargado no corresponde a una versión nueva de esta app.'
                    : 'No se ha podido completar la actualización. Inténtalo de nuevo.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          if (!downloading && !installing)
            TextButton(
              onPressed: onDismiss ?? () => Navigator.of(context).pop(),
              child: const Text('Ahora no'),
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
                  : 'Actualizar',
            ),
          ),
        ],
      ),
    );
  }
}
