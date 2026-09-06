import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../domain/achievement.dart';
import '../domain/achievement_ranking.dart';
import 'achievement_badge_assets.dart';

class AchievementCommunityRankingSection extends ConsumerWidget {
  const AchievementCommunityRankingSection({
    required this.definition,
    super.key,
  });

  final AchievementCategoryDefinition definition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(achievementRankingProvider(definition.id));
    return Card(
      key: const ValueKey('achievement-community-ranking'),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ranking.maybeWhen(
              data: (value) => _RankingHeader(
                ranking: value,
                onViewAll: value.entries.isEmpty
                    ? null
                    : () => _openFullRanking(context),
              ),
              orElse: () => const _RankingHeader(),
            ),
            const SizedBox(height: 5),
            ranking.when(
              data: (value) => value.entries.isEmpty
                  ? const _RankingMessage(
                      key: ValueKey('achievement-ranking-empty'),
                      message: 'Todavía no hay participantes.',
                    )
                  : Column(
                      children: [
                        for (final item in value.previewItems())
                          if (item.isGap)
                            const _RankingGap()
                          else
                            AchievementRankingRow(
                              entry: item.entry!,
                              definition: definition,
                              compact: true,
                            ),
                      ],
                    ),
              loading: () => const _RankingLoadingRows(),
              error: (_, _) => _RankingError(
                onRetry: () =>
                    ref.invalidate(achievementRankingProvider(definition.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullRanking(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AchievementRankingScreen(definition: definition),
      ),
    );
  }
}

class AchievementRankingScreen extends ConsumerStatefulWidget {
  const AchievementRankingScreen({required this.definition, super.key});

  final AchievementCategoryDefinition definition;

  @override
  ConsumerState<AchievementRankingScreen> createState() =>
      _AchievementRankingScreenState();
}

class _AchievementRankingScreenState
    extends ConsumerState<AchievementRankingScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ranking = ref.watch(achievementRankingProvider(widget.definition.id));
    final currentRank = ranking.valueOrNull?.currentUserEntry?.rank;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.definition.name} · Ranking'),
        actions: [
          if (currentRank != null)
            IconButton(
              tooltip: 'Ir a mi posición',
              onPressed: () => _scrollToRank(currentRank),
              icon: const Icon(Icons.my_location),
            ),
        ],
      ),
      body: SafeArea(
        child: ranking.when(
          data: (value) {
            if (value.entries.isEmpty) {
              return const Center(child: Text('Todavía no hay participantes.'));
            }
            return ListView.builder(
              key: const ValueKey('achievement-full-ranking-list'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemExtent: 61,
              itemCount: value.entries.length,
              itemBuilder: (context, index) => Column(
                children: [
                  AchievementRankingRow(
                    entry: value.entries[index],
                    definition: widget.definition,
                  ),
                  const Divider(height: 1),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton.icon(
              onPressed: () => ref.invalidate(
                achievementRankingProvider(widget.definition.id),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToRank(int rank) {
    if (!_scrollController.hasClients) {
      return;
    }
    final target = ((rank - 1) * 61.0)
        .clamp(0, _scrollController.position.maxScrollExtent)
        .toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }
}

class AchievementRankingRow extends StatelessWidget {
  const AchievementRankingRow({
    required this.entry,
    required this.definition,
    this.compact = false,
    super.key,
  });

  final AchievementRankingEntry entry;
  final AchievementCategoryDefinition definition;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final level = entry.levelFor(definition)?.id;
    return Material(
      key: ValueKey('achievement-ranking-row-${entry.userId}'),
      color: entry.isCurrentUser
          ? colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: entry.isCurrentUser
            ? null
            : () => context.push('/social-profile/${entry.userId}'),
        child: SizedBox(
          height: compact ? 46 : 60,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: entry.rank <= 3
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ProfileAvatar(
                  assetPath: entry.avatarAsset,
                  radius: compact ? 16 : 19,
                  isSelected: entry.isCurrentUser,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.isCurrentUser ? 'Tú' : entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: entry.isCurrentUser
                          ? FontWeight.w900
                          : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SvgPicture.asset(
                  baseAchievementBadgeAssetPath(level),
                  key: ValueKey(
                    'achievement-ranking-tier-${entry.userId}-${level?.name ?? 'locked'}',
                  ),
                  width: compact ? 34 : 40,
                  height: compact ? 34 : 40,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${entry.value}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: entry.isCurrentUser
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingHeader extends StatelessWidget {
  const _RankingHeader({this.ranking, this.onViewAll});

  final AchievementCommunityRanking? ranking;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final current = ranking?.currentUserEntry;
    final topPercent = ranking?.currentUserTopPercent;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ranking de la comunidad',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (current != null && topPercent != null)
                Text(
                  '#${current.rank} · Top $topPercent %',
                  key: const ValueKey('achievement-ranking-position-summary'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: onViewAll,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Ver todo'), Icon(Icons.chevron_right, size: 18)],
          ),
        ),
      ],
    );
  }
}

class _RankingGap extends StatelessWidget {
  const _RankingGap();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('achievement-ranking-gap'),
      height: 20,
      child: Center(
        child: Text(
          '···',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RankingLoadingRows extends StatelessWidget {
  const _RankingLoadingRows();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.75);
    return Column(
      key: const ValueKey('achievement-ranking-loading'),
      children: [
        for (var index = 0; index < 3; index++)
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Container(width: 28, height: 12, color: color),
                const SizedBox(width: 10),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 12, color: color)),
                const SizedBox(width: 28),
                Container(width: 40, height: 12, color: color),
              ],
            ),
          ),
      ],
    );
  }
}

class _RankingError extends StatelessWidget {
  const _RankingError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _RankingMessage(
      key: const ValueKey('achievement-ranking-error'),
      message: 'No se ha podido cargar el ranking.',
      action: TextButton(onPressed: onRetry, child: const Text('Reintentar')),
    );
  }
}

class _RankingMessage extends StatelessWidget {
  const _RankingMessage({required this.message, this.action, super.key});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
