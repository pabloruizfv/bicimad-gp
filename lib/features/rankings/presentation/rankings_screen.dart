import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/route_title.dart';
import '../domain/route_summary.dart';

class RankingsScreen extends ConsumerWidget {
  const RankingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(routeSummariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rankings')),
      body: SafeArea(
        child: AsyncStateView<List<RouteSummary>>(
          value: summariesAsync,
          data: (summaries) {
            if (summaries.isEmpty) {
              return const Center(
                child: Text('Todavía no hay rutas importadas.'),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: summaries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    onTap: () => context.push(
                      '/ranking/${summary.originStationId}/${summary.destinationStationId}',
                    ),
                    title: RouteTitle(
                      origin: summary.originStationName,
                      destination: summary.destinationStationName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Mejor personal: '
                        '${formatDurationSeconds(summary.personalBestDurationSeconds)}',
                      ),
                    ),
                    trailing: _RankingMetric(summary: summary),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RankingMetric extends StatelessWidget {
  const _RankingMetric({required this.summary});

  final RouteSummary summary;

  @override
  Widget build(BuildContext context) {
    final position = summary.currentUserPosition;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          position == null ? '-' : '#$position',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          '${summary.totalUsers} participantes',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
