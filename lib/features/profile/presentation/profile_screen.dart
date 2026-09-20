import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/app_identity.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../shared/widgets/checkered_flag_strip.dart';
import '../../../shared/widgets/menu_app_bar.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../data/avatar_repository.dart';
import '../../social/domain/social_profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final socialState = ref.watch(socialAuthControllerProvider);
    final socialProfile = socialState.profile;
    final avatarAsync = ref.watch(selectedAvatarProvider);
    final user = authState.user;
    final selectedAvatar =
        socialProfile?.avatarAsset ??
        avatarAsync.valueOrNull ??
        LocalAvatarRepository.defaultAvatarAsset;

    return Scaffold(
      appBar: const MenuAppBar(title: Text('Ajustes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(36),
                          onTap: () => _showAvatarPicker(
                            context,
                            ref,
                            selectedAvatar,
                            socialProfile,
                          ),
                          child: ProfileAvatar(
                            assetPath: selectedAvatar,
                            radius: 32,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Text(
                                      socialProfile?.displayName ??
                                          user?.displayName ??
                                          '-',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Cambiar nombre visible',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _renameProfile(
                                      context,
                                      ref,
                                      selectedAvatar,
                                      socialProfile,
                                      user?.displayName,
                                    ),
                                  ),
                                ],
                              ),
                              if (socialProfile != null)
                                Text(
                                  '@${socialProfile.username}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (socialProfile != null) ...[
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: socialProfile.isPublic,
                        onChanged: (isPublic) async {
                          final confirmed = await _confirmVisibilityChange(
                            context,
                            makePublic: isPublic,
                          );
                          if (confirmed != true || !context.mounted) {
                            return;
                          }
                          await ref
                              .read(socialAuthControllerProvider.notifier)
                              .updateProfile(
                                displayName: socialProfile.displayName,
                                avatarAsset: selectedAvatar,
                                isPublic: isPublic,
                              );
                        },
                        secondary: Icon(
                          socialProfile.isPublic
                              ? Icons.public
                              : Icons.lock_outline,
                        ),
                        title: Text(
                          socialProfile.isPublic
                              ? 'Perfil visible'
                              : 'Perfil oculto',
                        ),
                        subtitle: Text(
                          socialProfile.isPublic
                              ? 'Cualquiera puede ver tus estadísticas.'
                              : 'Solo tus seguidores pueden ver tus estadísticas.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SyncSettingsCard(
              lastSyncAt: authState.lastSyncAt,
              isSyncing: authState.isSyncing,
              onSync: () async {
                await ref
                    .read(authControllerProvider.notifier)
                    .synchronizeTrips();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sincronización completada.')),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(authControllerProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: authState.isLoading || authState.isSyncing
                  ? null
                  : () => _confirmAccountDeletion(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Eliminar mi cuenta'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAvatarPicker(
    BuildContext context,
    WidgetRef ref,
    String selectedAvatar,
    SocialProfile? socialProfile,
  ) {
    final repository = ref.read(avatarRepositoryProvider);
    return _showAvatarPickerSheet(
      context,
      selectedAsset: selectedAvatar,
      onSelected: (assetPath) async {
        if (socialProfile == null) {
          await repository.saveSelectedAvatar(assetPath);
          ref.invalidate(selectedAvatarProvider);
        } else {
          await ref
              .read(socialAuthControllerProvider.notifier)
              .updateProfile(
                displayName: socialProfile.displayName,
                avatarAsset: assetPath,
                isPublic: socialProfile.isPublic,
              );
        }
      },
    );
  }

  Future<void> _renameProfile(
    BuildContext context,
    WidgetRef ref,
    String selectedAvatar,
    SocialProfile? socialProfile,
    String? fallbackName,
  ) async {
    final newName = await _showRenameDialog(
      context,
      socialProfile?.displayName ?? fallbackName,
    );
    if (newName == null) {
      return;
    }
    if (socialProfile == null) {
      await ref
          .read(authControllerProvider.notifier)
          .completeDisplayName(newName);
    } else {
      await ref
          .read(socialAuthControllerProvider.notifier)
          .updateProfile(
            displayName: newName,
            avatarAsset: selectedAvatar,
            isPublic: socialProfile.isPublic,
          );
    }
  }

  Future<String?> _showRenameDialog(
    BuildContext context,
    String? currentName,
  ) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _RenameDialog(currentName: currentName);
      },
    );
  }

  Future<void> _confirmAccountDeletion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Eliminar mi cuenta'),
        content: const Text(
          'Se eliminarán permanentemente tu cuenta de $appDisplayName, tu '
          'perfil, todos tus viajes importados de este dispositivo y de la '
          'nube, tus estadísticas, seguidores, personas seguidas y '
          'solicitudes. También se eliminarán tus datos personales locales '
          'y se cerrarán todas las sesiones de la app.\n\n'
          'Esto no elimina tu cuenta ni tu historial original de '
          'BiciMAD/MPass, que pertenecen a un servicio externo.\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Eliminar mi cuenta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final deleted = await ref
        .read(authControllerProvider.notifier)
        .deleteMyAccount();
    if (!deleted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se ha podido eliminar tu cuenta. Inténtalo de nuevo.',
          ),
        ),
      );
    }
  }

  Future<bool?> _confirmVisibilityChange(
    BuildContext context, {
    required bool makePublic,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(makePublic ? Icons.public : Icons.lock_outline),
        title: Text(
          makePublic ? 'Cambiar a perfil visible' : 'Cambiar a perfil oculto',
        ),
        content: Text(
          makePublic
              ? 'Tu nombre público, @usuario y avatar seguirán apareciendo '
                    'en las búsquedas. Cualquier usuario podrá ver tus '
                    'estadísticas.\n\nTus viajes detallados siempre son privados.'
              : 'Tu nombre público, @usuario y avatar seguirán apareciendo '
                    'en las búsquedas. Solo tú y tus seguidores aceptados '
                    'podréis ver tus estadísticas. Las nuevas solicitudes '
                    'de seguimiento necesitarán tu aceptación.\n\nTus viajes '
                    'detallados siempre son privados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(makePublic ? 'Hacer visible' : 'Hacer oculto'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAvatarPickerSheet(
    BuildContext context, {
    required String selectedAsset,
    required Future<void> Function(String assetPath) onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return _AvatarPickerSheet(
          selectedAsset: selectedAsset,
          onSelected: (assetPath) async {
            Navigator.of(sheetContext).pop();
            await onSelected(assetPath);
          },
        );
      },
    );
  }
}

class _SyncSettingsCard extends StatelessWidget {
  const _SyncSettingsCard({
    required this.lastSyncAt,
    required this.isSyncing,
    required this.onSync,
  });

  final DateTime? lastSyncAt;
  final bool isSyncing;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sincronización',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Última sincronización: '
              '${lastSyncAt == null ? 'pendiente' : formatShortDateTime(lastSyncAt!)}',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: isSyncing ? null : onSync,
              icon: isSyncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('Sincronizar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.currentName});

  final String? currentName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nombre visible'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre visible'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Introduce un nombre visible.';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text);
    }
  }
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet({
    required this.selectedAsset,
    required this.onSelected,
  });

  final String selectedAsset;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CheckeredFlagStrip(height: 6),
              const SizedBox(height: 14),
              Text(
                'Selecciona tu avatar de piloto',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: LocalAvatarRepository.loadAvatarAssets(),
                  builder: (context, snapshot) {
                    final assets = snapshot.data ?? const <String>[];
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          alignment: WrapAlignment.center,
                          runAlignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final asset in assets)
                              Semantics(
                                label: 'Avatar ${asset.split('/').last}',
                                selected: selectedAsset == asset,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(40),
                                  onTap: () => onSelected(asset),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: ProfileAvatar(
                                      assetPath: asset,
                                      radius: 30,
                                      isSelected: selectedAsset == asset,
                                      emphasizeSelection: true,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
