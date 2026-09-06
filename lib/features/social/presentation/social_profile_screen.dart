import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../general/domain/station_usage.dart';
import '../../general/presentation/general_screen.dart';
import '../../achievements/presentation/achievement_detail_screen.dart';
import '../../achievements/presentation/achievement_showcase.dart';
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
            final currentProfile = ref.watch(currentSocialProfileProvider);
            final ownId = currentProfile?.userId;
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
                    mostUsedStationName: stats == null
                        ? null
                        : profile.mostUsedStationName,
                    onMostUsedStationTap:
                        stats == null || profile.mostUsedStationName == null
                        ? null
                        : () => _openMostUsedStationMap(
                            context,
                            ref,
                            profile.mostUsedStationName!,
                          ),
                    statistics: stats == null
                        ? null
                        : ProfileStatsCardData.fromStatistics(stats),
                    socialSummary: SocialConnectionSummary(
                      followersCount: value.followersCount,
                      followingCount: value.followingCount,
                      isPublic: profile.isPublic,
                    ),
                    socialAction: _FollowButton(profile: profile),
                    headToHeadAction: stats != null && profile.userId != ownId
                        ? HeadToHeadButton(
                            onTap: () =>
                                context.push('/head-to-head/${profile.userId}'),
                          )
                        : null,
                  ),
                  if (stats != null) ...[
                    const SizedBox(height: 12),
                    if (profile.userId == ownId)
                      ref
                          .watch(ownAchievementProgressProvider)
                          .when(
                            data: (progresses) => AchievementShowcase(
                              badges: [
                                for (final progress in progresses)
                                  AchievementBadgeViewData.fromProgress(
                                    progress,
                                  ),
                              ],
                              onBadgeTap: (index) =>
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          OwnAchievementDetailScreen(
                                            progress: progresses[index],
                                            avatarAsset: profile.avatarAsset,
                                          ),
                                    ),
                                  ),
                            ),
                            loading: () => const AchievementShowcaseLoading(),
                            error: (_, _) => const SizedBox.shrink(),
                          )
                    else
                      ref
                          .watch(
                            profileAchievementSummariesProvider(profile.userId),
                          )
                          .when(
                            data: (summaries) => AchievementShowcase(
                              badges: [
                                for (final summary in summaries)
                                  AchievementBadgeViewData.fromSummary(summary),
                              ],
                              onBadgeTap: (index) =>
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          PublicAchievementDetailScreen(
                                            summary: summaries[index],
                                          ),
                                    ),
                                  ),
                            ),
                            loading: () => const AchievementShowcaseLoading(),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                  ],
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

  Future<void> _openMostUsedStationMap(
    BuildContext context,
    WidgetRef ref,
    String stationName,
  ) async {
    final catalog = await ref
        .read(stationCatalogRepositoryProvider)
        .getCatalog();
    final station = catalog.resolve(stationId: '', stationName: stationName);
    if (station == null || !context.mounted) {
      return;
    }
    final usage = StationUsage(station: station, uses: 1);
    await showStationUsageMap(
      context,
      usages: [usage],
      showTiles: ref.read(stationUsageMapTilesEnabledProvider),
      initiallySelected: usage,
      title: 'Estación más usada',
      showUsageCounts: false,
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
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        maximumSize: const Size(double.infinity, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
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
