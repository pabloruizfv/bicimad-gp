import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/info_row.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final tripsAsync = ref.watch(myTripsProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: AsyncStateView(
          value: tripsAsync,
          data: (trips) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? '-',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'BiciMAD conectado — modo de demostración',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      InfoRow(
                        label: 'Viajes importados',
                        value: '${trips.length}',
                      ),
                      InfoRow(
                        label: 'Última sincronización',
                        value: authState.lastSyncAt == null
                            ? 'Pendiente'
                            : formatShortDateTime(authState.lastSyncAt!),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    _showRenameDialog(context, ref, user?.displayName),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Cambiar nombre visible'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).disconnect(),
                icon: const Icon(Icons.link_off),
                label: const Text('Desconectar BiciMAD'),
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
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String? currentName,
  ) async {
    final controller = TextEditingController(text: currentName ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nombre visible'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre visible'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Introduce un nombre visible.';
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(controller.text);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(controller.text);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result != null) {
      await ref
          .read(authControllerProvider.notifier)
          .completeDisplayName(result);
    }
  }
}
