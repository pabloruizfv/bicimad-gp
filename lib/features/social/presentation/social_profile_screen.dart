import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/arcade_user_stats_card.dart';
import '../domain/social_profile.dart';
import 'follow_confirmation.dart';

class SocialProfileScreen extends ConsumerWidget {
  const SocialProfileScreen({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(socialProfileDetailsProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: details.when(
          data: (value) {
            if (value == null) {
              return const Center(
                child: Text('Este perfil ya no está disponible.'),
              );
            }
            final profile = value.profile;
            final stats = value.statistics;
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(socialProfileDetailsProvider(userId)),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  ArcadeUserStatsCard(
                    avatarAsset: profile.avatarAsset,
                    displayName: profile.displayName,
                    username: profile.username,
                    statistics: stats == null
                        ? null
                        : ProfileStatsCardData.fromStatistics(stats),
                    socialSummary: SocialConnectionSummary(
                      followersCount: value.followersCount,
                      followingCount: value.followingCount,
                      isPublic: profile.isPublic,
                    ),
                    socialAction: _FollowButton(profile: profile),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton.icon(
              onPressed: () =>
                  ref.invalidate(socialProfileDetailsProvider(userId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.profile});
  final SocialProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownId = ref.watch(currentSocialProfileProvider)?.userId;
    if (ownId == profile.userId) {
      return const SizedBox.shrink();
    }
    final label = switch (profile.outgoingFollowStatus) {
      FollowStatus.accepted => 'Siguiendo',
      FollowStatus.pending => 'Pendiente',
      null => profile.isPublic ? 'Seguir' : 'Solicitar',
    };
    return FilledButton.tonal(
      onPressed: () async {
        if (profile.outgoingFollowStatus == FollowStatus.accepted) {
          final confirmed = await showFollowRemovalConfirmation(
            context,
            kind: FollowRemovalKind.unfollow,
            displayName: profile.displayName,
          );
          if (!confirmed || !context.mounted) {
            return;
          }
        }
        try {
          final repository = ref.read(socialRepositoryProvider);
          switch (profile.outgoingFollowStatus) {
            case FollowStatus.accepted:
              await repository.unfollow(profile.userId);
            case FollowStatus.pending:
              await repository.cancelFollow(profile.userId);
            case null:
              await repository.follow(profile.userId);
          }
          ref.invalidate(socialProfileDetailsProvider(profile.userId));
          if (ownId != null) {
            ref.invalidate(socialProfileDetailsProvider(ownId));
          }
          ref.invalidate(socialConnectionsProvider);
          ref.invalidate(socialSearchProvider);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se ha podido completar la acción.'),
              ),
            );
          }
        }
      },
      child: Text(label),
    );
  }
}
