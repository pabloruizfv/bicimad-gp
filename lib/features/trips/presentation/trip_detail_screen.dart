import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../shared/widgets/info_row.dart';
import '../../../shared/widgets/route_title.dart';
import '../../rankings/domain/route_key.dart';
import '../domain/trip.dart';

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({required this.tripId, super.key});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripByIdProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del viaje')),
      body: SafeArea(
        child: tripAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: (trip) {
            if (trip == null) {
              return const Center(child: Text('Viaje no encontrado.'));
            }
            return _TripDetailContent(trip: trip);
          },
        ),
      ),
    );
  }
}

class _TripDetailContent extends ConsumerWidget {
  const _TripDetailContent({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeKey = RouteKey(
      originStationId: trip.originStationId,
      destinationStationId: trip.destinationStationId,
    );
    final myTripsAsync = ref.watch(myTripsProvider);
    final sharedTripsAsync = ref.watch(sharedTripsProvider);
    final rankingAsync = ref.watch(routeRankingProvider(routeKey));

    if (myTripsAsync.isLoading ||
        sharedTripsAsync.isLoading ||
        rankingAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (myTripsAsync.hasError) {
      return Center(child: Text(myTripsAsync.error.toString()));
    }
    if (sharedTripsAsync.hasError) {
      return Center(child: Text(sharedTripsAsync.error.toString()));
    }
    if (rankingAsync.hasError) {
      return Center(child: Text(rankingAsync.error.toString()));
    }

    final myTrips = myTripsAsync.requireValue;
    final sharedTrips = sharedTripsAsync.requireValue;
    final ranking = rankingAsync.requireValue;
    final rankingService = ref.watch(rankingServiceProvider);
    final personalBest = rankingService.personalBestForRoute(
      trips: myTrips,
      targetTrip: trip,
    );
    final percentSlower = rankingService.percentOfCommunityTripsSlower(
      trip: trip,
      sharedTrips: sharedTrips,
    );
    final position = ranking.currentUserPosition;
    final shareText =
        'He hecho ${trip.originStationName} → ${trip.destinationStationName} '
        'en ${formatDurationSeconds(trip.durationSeconds)}. '
        'Posición ${position ?? '-'} de ${ranking.totalUsers} en la comunidad.';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RouteTitle(
                  origin: trip.originStationName,
                  destination: trip.destinationStationName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(formatShortDateTime(trip.startedAt)),
                const SizedBox(height: 18),
                InfoRow(
                  label: 'Duración del viaje',
                  value: formatDurationSeconds(trip.durationSeconds),
                ),
                InfoRow(
                  label: 'Mejor tiempo personal',
                  value: personalBest == null
                      ? '-'
                      : formatDurationSeconds(personalBest.durationSeconds),
                ),
                InfoRow(
                  label: 'Posición en ranking',
                  value: position == null
                      ? '- de ${ranking.totalUsers}'
                      : '$position de ${ranking.totalUsers}',
                ),
                InfoRow(
                  label: 'Viajes comunitarios más lentos',
                  value: '${percentSlower.round()}%',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.push(
            '/ranking/${trip.originStationId}/${trip.destinationStationId}',
          ),
          icon: const Icon(Icons.leaderboard),
          label: const Text('Ver ranking completo'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            SharePlus.instance.share(ShareParams(text: shareText));
          },
          icon: const Icon(Icons.ios_share),
          label: const Text('Compartir'),
        ),
      ],
    );
  }
}
