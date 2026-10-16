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
        updateState.status == AppUpdateStatus.available;

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
    if (state.status != AppUpdateStatus.available ||
        state.info?.latestVersion == _deferredUpdateVersion ||
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
    return AlertDialog(
      title: const Text('Nueva versión disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info == null
                ? 'Puedes actualizar BiciMAD GP.'
                : 'Tienes la versión ${info.currentVersion}. La versión '
                      '${info.latestVersion} ya está disponible en GitHub.',
          ),
          if (state.isUnsupported)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Esta versión ya no está entre las versiones compatibles. '
                'Si no actualizas, algunas funciones pueden no comportarse '
                'como se espera.',
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismiss ?? () => Navigator.of(context).pop(),
          child: const Text('Ahora no'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final opened = await ref
                .read(appUpdateControllerProvider.notifier)
                .openReleasePage();
            if (!context.mounted) return;
            if (opened) {
              (onDismiss ?? () => Navigator.of(context).pop())();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se ha podido abrir GitHub.')),
              );
            }
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('Ir a GitHub'),
        ),
      ],
    );
  }
}
