import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/technical_config_resolver.dart';

class ExperimentalConfigScreen extends ConsumerStatefulWidget {
  const ExperimentalConfigScreen({super.key});

  @override
  ConsumerState<ExperimentalConfigScreen> createState() =>
      _ExperimentalConfigScreenState();
}

class _ExperimentalConfigScreenState
    extends ConsumerState<ExperimentalConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passKeyController = TextEditingController();
  final _xClientIdController = TextEditingController();

  @override
  void dispose() {
    _passKeyController.dispose();
    _xClientIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(technicalConfigStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración experimental')),
      body: SafeArea(
        child: status.when(
          data: (resolved) {
            if (resolved.source == TechnicalConfigSource.build) {
              return const _BuildConfigView();
            }
            return _SecureStorageConfigView(
              resolved: resolved,
              formKey: _formKey,
              passKeyController: _passKeyController,
              xClientIdController: _xClientIdController,
              onSave: _save,
              onClear: _clear,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No se ha podido comprobar la configuración.'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await ref
        .read(bicimadSecureStorageProvider)
        .saveTechnicalConfig(
          passKey: _passKeyController.text,
          xClientId: _xClientIdController.text,
        );
    _passKeyController.clear();
    _xClientIdController.clear();
    ref.invalidate(technicalConfigStatusProvider);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuración guardada.')));
    }
  }

  Future<void> _clear() async {
    await ref.read(bicimadSecureStorageProvider).clearTechnicalConfig();
    _passKeyController.clear();
    _xClientIdController.clear();
    ref.invalidate(technicalConfigStatusProvider);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuración eliminada.')));
    }
  }
}

class _BuildConfigView extends StatelessWidget {
  const _BuildConfigView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Configuración técnica incluida en esta compilación.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Para modificarla es necesario detener la app y recompilar con nuevos valores.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SecureStorageConfigView extends StatelessWidget {
  const _SecureStorageConfigView({
    required this.resolved,
    required this.formKey,
    required this.passKeyController,
    required this.xClientIdController,
    required this.onSave,
    required this.onClear,
  });

  final ResolvedTechnicalConfig resolved;
  final GlobalKey<FormState> formKey;
  final TextEditingController passKeyController;
  final TextEditingController xClientIdController;
  final Future<void> Function() onSave;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final isConfigured = resolved.isConfigured;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isConfigured
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: isConfigured
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConfigured
                        ? 'Configuración técnica guardada.'
                        : 'Falta la configuración técnica experimental.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: passKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'passKey',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
                validator: _requiredValue,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: xClientIdController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'X-ClientId',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                validator: _requiredValue,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar configuración'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar configuración'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _requiredValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Introduce este valor técnico.';
    }
    return null;
  }
}
