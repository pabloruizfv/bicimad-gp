import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../profile/data/avatar_repository.dart';

class SocialOnboardingScreen extends ConsumerStatefulWidget {
  const SocialOnboardingScreen({super.key});

  @override
  ConsumerState<SocialOnboardingScreen> createState() =>
      _SocialOnboardingScreenState();
}

class _SocialOnboardingScreenState
    extends ConsumerState<SocialOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _nameController = TextEditingController();
  String _avatar = LocalAvatarRepository.defaultAvatarAsset;
  bool _isPublic = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialAuthControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tu perfil social')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Elige cómo te verá la comunidad',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _usernameController,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '@usuario',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (value) =>
                    RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Usa 3–20 minúsculas, números o guion bajo.',
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Nombre público',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  return name.isEmpty || name.length > 40
                      ? 'Introduce un nombre de 1–40 caracteres.'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Avatar',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<String>>(
                future: LocalAvatarRepository.loadAvatarAssets(),
                builder: (context, snapshot) {
                  final assets = snapshot.data ?? const <String>[];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    alignment: WrapAlignment.center,
                    runAlignment: WrapAlignment.center,
                    children: [
                      for (final asset in assets)
                        InkWell(
                          borderRadius: BorderRadius.circular(40),
                          onTap: () => setState(() => _avatar = asset),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: ProfileAvatar(
                              assetPath: asset,
                              radius: 30,
                              isSelected: asset == _avatar,
                              emphasizeSelection: true,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              SwitchListTile(
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
                title: const Text('Perfil visible'),
                subtitle: Text(
                  _isPublic
                      ? 'La comunidad podrá ver tus estadísticas.'
                      : 'Solo seguidores aceptados verán tus estadísticas.',
                ),
                secondary: Icon(_isPublic ? Icons.public : Icons.lock_outline),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Crear perfil'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    ref
        .read(socialAuthControllerProvider.notifier)
        .createProfile(
          username: _usernameController.text,
          displayName: _nameController.text,
          avatarAsset: _avatar,
          isPublic: _isPublic,
        );
  }
}
