import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/route_title.dart';
import '../domain/route_key.dart';
import '../domain/route_ranking.dart';

class RankingDetailScreen extends ConsumerWidget {
  const RankingDetailScreen({required this.routeKey, super.key});

  final RouteKey routeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(routeRankingProvider(routeKey));

    return Scaffold(
      appBar: AppBar(title: const Text('Ranking completo')),
      body: SafeArea(
        child: AsyncStateView<RouteRanking>(
          value: rankingAsync,
          data: (ranking) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RouteTitle(
                        origin: ranking.originStationName,
                        destination: ranking.destinationStationName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text('${ranking.totalUsers} participantes'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              for (final entry in ranking.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: entry.isCurrentUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surface,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: entry.isCurrentUser
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        foregroundColor: entry.isCurrentUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface,
                        child: Text('${entry.position}'),
                      ),
                      title: Text(
                        entry.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: entry.isCurrentUser
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                      ),
                      trailing: Text(
                        formatDurationSeconds(entry.bestDurationSeconds),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
