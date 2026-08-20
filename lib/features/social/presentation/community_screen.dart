import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/menu_app_bar.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../domain/follow_connection.dart';
import '../domain/social_profile.dart';
import 'follow_confirmation.dart';

enum CommunityTab { search, followers, following, requests }

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({this.initialTab = CommunityTab.search, super.key});

  final CommunityTab initialTab;

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        appBar: const MenuAppBar(title: Text('Comunidad')),
        body: SafeArea(
          child: Column(
            children: [
              const Material(
                color: Colors.white,
                child: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(icon: Icon(Icons.search), text: 'Buscar'),
                    Tab(icon: Icon(Icons.people_outline), text: 'Seguidores'),
                    Tab(icon: Icon(Icons.person_add_alt), text: 'Siguiendo'),
                    Tab(icon: Icon(Icons.inbox_outlined), text: 'Solicitudes'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSearch(),
                    const _ConnectionsView(type: ConnectionListType.followers),
                    const _ConnectionsView(type: ConnectionListType.following),
                    const _RequestsView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    final results = ref.watch(socialSearchProvider(_query));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Buscar @usuario o nombre',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() => _query = value.trim());
                }
              });
            },
          ),
        ),
        Expanded(
          child: _query.length < 2
              ? const _EmptySocialState(
                  icon: Icons.manage_search,
                  message: 'Escribe al menos dos caracteres.',
                )
              : results.when(
                  data: (profiles) => profiles.isEmpty
                      ? const _EmptySocialState(
                          icon: Icons.person_search_outlined,
                          message: 'No se han encontrado perfiles.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(socialSearchProvider(_query)),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: profiles.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) => _ProfileTile(
                              profile: profiles[index],
                              action: _searchAction(profiles[index]),
                            ),
                          ),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _ErrorSocialState(
                    onRetry: () => ref.invalidate(socialSearchProvider(_query)),
                  ),
                ),
        ),
      ],
    );
  }

  _ProfileAction _searchAction(SocialProfile profile) {
    return switch (profile.outgoingFollowStatus) {
      FollowStatus.accepted => _ProfileAction(
        label: 'Dejar de seguir',
        icon: Icons.person_remove_outlined,
        onPressed: () async {
          final confirmed = await showFollowRemovalConfirmation(
            context,
            kind: FollowRemovalKind.unfollow,
            displayName: profile.displayName,
          );
          if (!confirmed || !mounted) {
            return;
          }
          await _runAction(
            () => ref.read(socialRepositoryProvider).unfollow(profile.userId),
          );
        },
      ),
      FollowStatus.pending => _ProfileAction(
        label: 'Cancelar',
        icon: Icons.close,
        onPressed: () => _runAction(
          () => ref.read(socialRepositoryProvider).cancelFollow(profile.userId),
        ),
      ),
      null => _ProfileAction(
        label: profile.isPublic ? 'Seguir' : 'Solicitar',
        icon: Icons.person_add_alt,
        onPressed: () => _runAction(
          () => ref.read(socialRepositoryProvider).follow(profile.userId),
        ),
      ),
    };
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      _invalidateSocialLists(ref);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se ha podido completar la acción.')),
        );
      }
    }
  }
}

class _ConnectionsView extends ConsumerWidget {
  const _ConnectionsView({required this.type});

  final ConnectionListType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(socialConnectionsProvider(type));
    return connections.when(
      data: (items) => items.isEmpty
          ? _EmptySocialState(
              icon: type == ConnectionListType.followers
                  ? Icons.people_outline
                  : Icons.person_add_alt,
              message: type == ConnectionListType.followers
                  ? 'Aún no tienes seguidores.'
                  : 'Aún no sigues a nadie.',
            )
          : RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(socialConnectionsProvider(type)),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final connection = items[index];
                  final isFollower = type == ConnectionListType.followers;
                  return _ProfileTile(
                    profile: connection.profile,
                    action: _ProfileAction(
                      label: isFollower ? 'Eliminar' : 'Dejar de seguir',
                      icon: Icons.person_remove_outlined,
                      onPressed: () async {
                        final confirmed = await showFollowRemovalConfirmation(
                          context,
                          kind: isFollower
                              ? FollowRemovalKind.removeFollower
                              : FollowRemovalKind.unfollow,
                          displayName: connection.profile.displayName,
                        );
                        if (!confirmed || !context.mounted) {
                          return;
                        }
                        await _connectionAction(
                          context,
                          ref,
                          () => isFollower
                              ? ref
                                    .read(socialRepositoryProvider)
                                    .removeFollower(connection.profile.userId)
                              : ref
                                    .read(socialRepositoryProvider)
                                    .unfollow(connection.profile.userId),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorSocialState(
        onRetry: () => ref.invalidate(socialConnectionsProvider(type)),
      ),
    );
  }
}

class _RequestsView extends ConsumerWidget {
  const _RequestsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final received = ref.watch(
      socialConnectionsProvider(ConnectionListType.receivedRequests),
    );
    final sent = ref.watch(
      socialConnectionsProvider(ConnectionListType.sentRequests),
    );
    if (received.isLoading || sent.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (received.hasError || sent.hasError) {
      return _ErrorSocialState(onRetry: () => _invalidateSocialLists(ref));
    }
    final receivedItems = received.valueOrNull ?? const <FollowConnection>[];
    final sentItems = sent.valueOrNull ?? const <FollowConnection>[];
    if (receivedItems.isEmpty && sentItems.isEmpty) {
      return const _EmptySocialState(
        icon: Icons.inbox_outlined,
        message: 'No tienes solicitudes pendientes.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _invalidateSocialLists(ref),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (receivedItems.isNotEmpty) ...[
            const _SectionTitle('Recibidas'),
            for (final item in receivedItems)
              _RequestTile(connection: item, received: true),
          ],
          if (sentItems.isNotEmpty) ...[
            const _SectionTitle('Enviadas'),
            for (final item in sentItems)
              _RequestTile(connection: item, received: false),
          ],
        ],
      ),
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.connection, required this.received});

  final FollowConnection connection;
  final bool received;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ProfileAvatar(
              assetPath: connection.profile.avatarAsset,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('@${connection.profile.username}'),
                ],
              ),
            ),
            if (received) ...[
              IconButton(
                tooltip: 'Rechazar',
                onPressed: () => _connectionAction(
                  context,
                  ref,
                  () => ref
                      .read(socialRepositoryProvider)
                      .rejectFollow(connection.profile.userId),
                ),
                icon: const Icon(Icons.close),
              ),
              IconButton.filled(
                tooltip: 'Aceptar',
                onPressed: () => _connectionAction(
                  context,
                  ref,
                  () => ref
                      .read(socialRepositoryProvider)
                      .acceptFollow(connection.profile.userId),
                ),
                icon: const Icon(Icons.check),
              ),
            ] else
              TextButton(
                onPressed: () => _connectionAction(
                  context,
                  ref,
                  () => ref
                      .read(socialRepositoryProvider)
                      .cancelFollow(connection.profile.userId),
                ),
                child: const Text('Cancelar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.action});

  final SocialProfile profile;
  final _ProfileAction action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/social-profile/${profile.userId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProfileAvatar(assetPath: profile.avatarAsset, radius: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Row(
                      children: [
                        Flexible(child: Text('@${profile.username}')),
                        if (!profile.isPublic) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.lock_outline, size: 15),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: action.label,
                onPressed: action.onPressed,
                icon: Icon(action.icon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAction {
  const _ProfileAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    ),
  );
}

class _EmptySocialState extends StatelessWidget {
  const _EmptySocialState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _ErrorSocialState extends StatelessWidget {
  const _ErrorSocialState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('No se han podido cargar los datos sociales.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _connectionAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  try {
    await action();
    _invalidateSocialLists(ref);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se ha podido completar la acción.')),
      );
    }
  }
}

void _invalidateSocialLists(WidgetRef ref) {
  ref.invalidate(socialConnectionsProvider);
  ref.invalidate(socialSearchProvider);
  final ownId = ref.read(currentSocialProfileProvider)?.userId;
  if (ownId != null) {
    ref.invalidate(socialProfileDetailsProvider(ownId));
  }
}
