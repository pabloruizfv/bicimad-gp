import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/utils/decimal_amount.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../core/utils/metric_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/menu_app_bar.dart';
import '../../../shared/widgets/metric_pill.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../../shared/widgets/trip_sync_progress_banner.dart';
import '../../profile/data/avatar_repository.dart';
import '../domain/trip.dart';

const tripRankGoldAccent = Color(0xFFE6B800);
const tripRankSilverAccent = Color(0xFFADB5BD);
const tripRankBronzeAccent = Color(0xFFB56A35);

Color tripRankAccentColor(int rank) => switch (rank) {
  1 => tripRankGoldAccent,
  2 => tripRankSilverAccent,
  3 => tripRankBronzeAccent,
  _ => Colors.black,
};

Color tripRankBackgroundColor(int rank) => switch (rank) {
  1 => const Color(0xFFFFF8D6),
  2 => const Color(0xFFF3F4F6),
  3 => const Color(0xFFFFF0E2),
  _ => Colors.transparent,
};

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    final avatarAsync = ref.watch(selectedAvatarProvider);
    final avatarAsset =
        avatarAsync.valueOrNull ?? LocalAvatarRepository.defaultAvatarAsset;

    return Scaffold(
      appBar: const MenuAppBar(title: Text('Mis viajes')),
      body: SafeArea(
        child: AsyncStateView<List<Trip>>(
          value: tripsAsync,
          data: (trips) => Column(
            children: [
              const _SyncProgressSection(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref
                      .read(authControllerProvider.notifier)
                      .synchronizeTrips(),
                  child: TripsListView(trips: trips, avatarAsset: avatarAsset),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripsListView extends StatelessWidget {
  const TripsListView({
    required this.trips,
    required this.avatarAsset,
    super.key,
  });

  final List<Trip> trips;
  final String avatarAsset;

  @override
  Widget build(BuildContext context) {
    final bestByRoute = <String, int>{};
    for (final trip in trips) {
      final key = '${trip.originStationId}\u0000${trip.destinationStationId}';
      final current = bestByRoute[key];
      if (current == null || trip.durationSeconds < current) {
        bestByRoute[key] = trip.durationSeconds;
      }
    }

    return ListView.separated(
      key: const ValueKey('lazy-trips-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: trips.isEmpty ? 1 : trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (trips.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No hay viajes disponibles.'),
            ),
          );
        }
        final trip = trips[index];
        final routeKey =
            '${trip.originStationId}\u0000${trip.destinationStationId}';
        return TripCard(
          key: ValueKey('trip-list-item-${trip.id}'),
          trip: trip,
          isPersonalRecord: bestByRoute[routeKey] == trip.durationSeconds,
          avatarAsset: avatarAsset,
          onTap: () => context.push(
            '/route-history/'
            '${Uri.encodeComponent(trip.originStationId)}/'
            '${Uri.encodeComponent(trip.destinationStationId)}'
            '?selectedTripId=${Uri.encodeQueryComponent(trip.id)}',
          ),
        );
      },
    );
  }
}

class _SyncProgressSection extends ConsumerWidget {
  const _SyncProgressSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      authControllerProvider.select((state) => state.syncProgress),
    );
    if (progress == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TripSyncProgressBanner(progress: progress),
    );
  }
}

class TripCard extends StatelessWidget {
  const TripCard({
    required this.trip,
    required this.isPersonalRecord,
    required this.avatarAsset,
    this.showRoute = true,
    this.isSelected = false,
    this.embedded = false,
    this.medalRank,
    this.showHistoricalPercentile = false,
    this.historicalPercentile,
    this.onTap,
    super.key,
  });

  final Trip trip;
  final bool isPersonalRecord;
  final String avatarAsset;
  final bool showRoute;
  final bool isSelected;
  final bool embedded;
  final int? medalRank;
  final bool showHistoricalPercentile;
  final double? historicalPercentile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final content = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TripAvatarIcon(assetPath: avatarAsset),
            const SizedBox(width: 12),
            Expanded(
              child: _TripCardText(
                trip: trip,
                isPersonalRecord: isPersonalRecord,
                medalRank: medalRank,
                showRoute: showRoute,
                showHistoricalPercentile: showHistoricalPercentile,
                historicalPercentile: historicalPercentile,
                textTheme: textTheme,
              ),
            ),
          ],
        ),
      ),
    );

    if (embedded) {
      return SizedBox(
        width: double.infinity,
        child: Material(
          color: isSelected
              ? Color.alphaBlend(
                  colorScheme.error.withValues(alpha: 0.08),
                  colorScheme.surface,
                )
              : medalRank == null
              ? Colors.transparent
              : tripRankBackgroundColor(medalRank!),
          child: DecoratedBox(
            key: ValueKey('trip-card-selection-${trip.id}'),
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: colorScheme.error, width: 2)
                  : null,
            ),
            child: content,
          ),
        ),
      );
    }

    return Card(
      color: isSelected
          ? Color.alphaBlend(
              colorScheme.error.withValues(alpha: 0.08),
              colorScheme.surface,
            )
          : null,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: colorScheme.error, width: 2),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _TripCardText extends StatelessWidget {
  const _TripCardText({
    required this.trip,
    required this.isPersonalRecord,
    required this.medalRank,
    required this.showRoute,
    required this.showHistoricalPercentile,
    required this.historicalPercentile,
    required this.textTheme,
  });

  final Trip trip;
  final bool isPersonalRecord;
  final int? medalRank;
  final bool showRoute;
  final bool showHistoricalPercentile;
  final double? historicalPercentile;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final titleStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.12,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${formatShortDateTime(trip.startedAt)} - '
                  '${formatShortTime(trip.endedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isPositiveDecimalAmount(trip.tripCost)) ...[
                const SizedBox(width: 8),
                _TripPricePill(tripId: trip.id, tripCost: trip.tripCost!),
              ],
              if (medalRank != null) ...[
                const SizedBox(width: 8),
                _PlacementMedalPill(rank: medalRank!),
              ] else if (isPersonalRecord) ...[
                const SizedBox(width: 8),
                const _PersonalRecordPill(),
              ],
            ],
          ),
        ),
        if (showRoute) ...[
          const SizedBox(height: 8),
          _TripRouteStop(name: trip.originStationName, style: titleStyle),
          for (var index = 0; index < trip.pitStops.length; index++) ...[
            const _TripRouteArrow(),
            _TripRouteStop(
              name: trip.pitStops[index].stationName,
              style: titleStyle,
              trailing: _PitStopDurationPill(
                seconds: trip.pitStops[index].durationSeconds,
              ),
            ),
          ],
          const _TripRouteArrow(),
          _TripRouteStop(name: trip.destinationStationName, style: titleStyle),
        ] else if (trip.hasPitStops) ...[
          const SizedBox(height: 8),
          for (final pitStop in trip.pitStops)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _PitStopSummaryPill(
                stationName: pitStop.stationName,
                durationSeconds: pitStop.durationSeconds,
              ),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (showHistoricalPercentile)
              MetricPill(
                icon: Icons.leaderboard_outlined,
                label: historicalPercentile == null
                    ? 'P--'
                    : 'P${historicalPercentile!.clamp(0, 100).round()}',
                dense: true,
              )
            else
              MetricPill(
                icon: Icons.route_outlined,
                label: formatDistanceMeters(trip.directDistanceMeters),
                dense: true,
              ),
            MetricPill(
              icon: Icons.timer_outlined,
              label: formatDurationSeconds(trip.durationSeconds),
              dense: true,
            ),
            MetricPill(
              icon: Icons.speed_outlined,
              label: formatSpeedKmh(trip.equivalentAverageSpeedKmh),
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _TripPricePill extends StatelessWidget {
  const _TripPricePill({required this.tripId, required this.tripCost});

  final String tripId;
  final String tripCost;

  @override
  Widget build(BuildContext context) {
    return MetricPill(
      key: ValueKey('trip-price-pill-$tripId'),
      icon: Icons.payments_outlined,
      label: '-${formatDecimalEuros(tripCost)}',
      backgroundColor: const Color(0xFFFFE3E3),
      foregroundColor: const Color(0xFF9B1C1C),
      borderColor: const Color(0xFFE57373),
      dense: true,
    );
  }
}

class _PitStopSummaryPill extends StatelessWidget {
  const _PitStopSummaryPill({
    required this.stationName,
    required this.durationSeconds,
  });

  final String stationName;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerLeft,
        child: MetricPill(
          icon: Icons.local_gas_station_outlined,
          label: '${formatDurationSeconds(durationSeconds)}  ·  $stationName',
          backgroundColor: const Color(0xFFDDF3EE),
          foregroundColor: const Color(0xFF075E56),
          borderColor: const Color(0xFF91D5C8),
          maxWidth: constraints.maxWidth,
          dense: true,
        ),
      ),
    );
  }
}

class _PlacementMedalPill extends StatelessWidget {
  const _PlacementMedalPill({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (rank) {
      1 => (bicimadArcadeYellow, const Color(0xFF503D00), tripRankGoldAccent),
      2 => (
        const Color(0xFFE4E7EB),
        const Color(0xFF4B5563),
        tripRankSilverAccent,
      ),
      _ => (
        const Color(0xFFE8B07A),
        const Color(0xFF693514),
        tripRankBronzeAccent,
      ),
    };

    return DecoratedBox(
      key: ValueKey('trip-rank-medal-$rank'),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Icon(Icons.workspace_premium, size: 15, color: foreground),
      ),
    );
  }
}

class _TripRouteStop extends StatelessWidget {
  const _TripRouteStop({
    required this.name,
    required this.style,
    this.trailing,
  });

  final String name;
  final TextStyle? style;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class _TripRouteArrow extends StatelessWidget {
  const _TripRouteArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Icon(
        Icons.keyboard_arrow_down,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _PitStopDurationPill extends StatelessWidget {
  const _PitStopDurationPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return MetricPill(
      icon: Icons.local_gas_station_outlined,
      label: formatDurationSeconds(seconds),
      backgroundColor: const Color(0xFFDDF3EE),
      foregroundColor: const Color(0xFF075E56),
      borderColor: const Color(0xFF91D5C8),
      dense: true,
    );
  }
}

class _PersonalRecordPill extends StatelessWidget {
  const _PersonalRecordPill();

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFF503D00);

    return DecoratedBox(
      key: const ValueKey('personal-record-medal'),
      decoration: BoxDecoration(
        color: bicimadArcadeYellow,
        border: Border.all(color: const Color(0xFFE6B800)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: const Icon(Icons.workspace_premium, size: 15, color: foreground),
      ),
    );
  }
}

class _TripAvatarIcon extends StatelessWidget {
  const _TripAvatarIcon({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 58,
      child: Center(child: ProfileAvatar(assetPath: assetPath, radius: 22)),
    );
  }
}
