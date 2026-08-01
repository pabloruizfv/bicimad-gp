import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/route_title.dart';
import '../domain/trip.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis viajes')),
      body: SafeArea(
        child: AsyncStateView<List<Trip>>(
          value: tripsAsync,
          data: (trips) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _SyncHeader(lastSyncAt: authState.lastSyncAt),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: authState.isSyncing
                    ? null
                    : () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .synchronizeTrips();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Sincronización simulada completada.',
                              ),
                            ),
                          );
                        }
                      },
                icon: authState.isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Sincronizar'),
              ),
              const SizedBox(height: 16),
              for (final trip in trips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TripCard(
                    trip: trip,
                    isPersonalRecord: ref
                        .watch(rankingServiceProvider)
                        .isPersonalRecord(trips: trips, targetTrip: trip),
                    onTap: () => context.push('/trip/${trip.id}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripCard extends StatelessWidget {
  const TripCard({
    required this.trip,
    required this.isPersonalRecord,
    this.onTap,
    super.key,
  });

  final Trip trip;
  final bool isPersonalRecord;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: RouteTitle(
          origin: trip.originStationName,
          destination: trip.destinationStationName,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(formatShortDateTime(trip.startedAt)),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatDurationSeconds(trip.durationSeconds),
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isPersonalRecord)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Récord personal',
                  style: textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SyncHeader extends StatelessWidget {
  const _SyncHeader({required this.lastSyncAt});

  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.cloud_done_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Última sincronización simulada: '
                '${lastSyncAt == null ? 'pendiente' : formatShortDateTime(lastSyncAt!)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
