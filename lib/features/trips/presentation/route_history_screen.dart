import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../app/providers.dart';
import '../../../core/config/carto_basemap_config.dart';
import '../../../core/utils/decimal_amount.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/duration_axis_ticks.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/utils/metric_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/checkered_flag_strip.dart';
import '../../../shared/widgets/docking_station_icon.dart';
import '../../../shared/widgets/info_row.dart';
import '../../../shared/widgets/metric_pill.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../profile/data/avatar_repository.dart';
import '../../rankings/domain/community_route_ranking.dart';
import '../../rankings/domain/route_key.dart';
import '../domain/legacy_route_model.dart';
import '../domain/route_statistics.dart';
import '../domain/trip.dart';
import 'trips_screen.dart';

class RouteHistoryScreen extends ConsumerWidget {
  const RouteHistoryScreen({
    required this.routeKey,
    this.selectedTripId,
    this.showOverview = true,
    this.allowTripNavigation = false,
    this.startInCommunity = false,
    super.key,
  });

  final RouteKey routeKey;
  final String? selectedTripId;
  final bool showOverview;
  final bool allowTripNavigation;
  final bool startInCommunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(routeTripsProvider(routeKey));
    final AsyncValue<LegacyRouteModel?> legacyModelAsync = showOverview
        ? const AsyncData<LegacyRouteModel?>(null)
        : ref.watch(legacyRouteModelProvider(routeKey));
    final AsyncValue<List<Trip>> allTripsAsync = showOverview
        ? ref.watch(myRankingTripsProvider)
        : const AsyncData<List<Trip>>(<Trip>[]);
    final AsyncValue<List<Trip>> stagesAsync = showOverview
        ? ref.watch(myTripStagesProvider)
        : const AsyncData<List<Trip>>(<Trip>[]);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: Text(
          '${showOverview ? 'Viaje' : 'Ranking'} '
          '${routeKey.originStationId} → ${routeKey.destinationStationId}',
        ),
      ),
      body: SafeArea(
        child: AsyncStateView<List<Trip>>(
          value: tripsAsync,
          data: (trips) {
            if (trips.isEmpty) {
              return const Center(
                child: Text('No hay viajes guardados para esta ruta.'),
              );
            }

            final statistics = RouteStatistics.fromTrips(trips);
            final selectedTrip =
                trips.where((trip) => trip.id == selectedTripId).firstOrNull ??
                trips.first;
            final avatarAsync = ref.watch(selectedAvatarProvider);
            final avatarAsset =
                avatarAsync.valueOrNull ??
                LocalAvatarRepository.defaultAvatarAsset;
            final selectedStages = _stagesForJourney(
              selectedTrip,
              stagesAsync.valueOrNull ?? const [],
            );
            final stageNavigationTargets = _stageNavigationTargets(
              selectedTrip: selectedTrip,
              stages: selectedStages,
              rankingTrips: allTripsAsync.valueOrNull ?? const [],
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (showOverview) ...[
                  _RouteOverviewCard(
                    trip: selectedTrip,
                    stages: selectedStages,
                    stageNavigationTargets: stageNavigationTargets,
                    onOpenTrip: (trip) =>
                        context.push(_tripDetailLocation(trip)),
                    onOpenParentJourney: selectedTrip.isJourneyProjection
                        ? () => context.push(
                            _parentJourneyDetailLocation(selectedTrip),
                          )
                        : null,
                    personalContext: allTripsAsync.when(
                      loading: () => const _TripContextLoadingSection(),
                      error: (error, stackTrace) =>
                          const _TripContextErrorSection(),
                      data: (allTrips) => _TripPersonalContextSection(
                        trip: selectedTrip,
                        routeTrips: trips,
                        allTrips: allTrips,
                      ),
                    ),
                  ),
                ] else ...[
                  _GenericRouteOverviewCard(trip: selectedTrip),
                  const SizedBox(height: 16),
                  _LegacyHistorySection(
                    routeKey: routeKey,
                    modelAsync: legacyModelAsync,
                    personalTrips: trips,
                    personalStatistics: statistics,
                    avatarAsset: avatarAsset,
                    onTripSelected: allowTripNavigation
                        ? (trip) => context.push(_tripDetailLocation(trip))
                        : null,
                    startInCommunity: startInCommunity,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GenericRouteOverviewCard extends StatelessWidget {
  const _GenericRouteOverviewCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stops = _genericRouteStops(trip, colorScheme);
    final distance =
        trip.directDistanceMeters ?? _distanceBetween(stops.first, stops.last);
    final hasCoordinates = stops.every(
      (stop) => stop.latitude != null && stop.longitude != null,
    );

    return Card(
      key: const ValueKey('generic-route-overview-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 8,
            color: colorScheme.primary,
            child: const CheckeredFlagStrip(height: 8),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteStopRow(stop: stops.first),
                _GenericRouteConnectionRow(
                  distanceMeters: distance,
                  color: colorScheme.primary,
                ),
                _RouteStopRow(stop: stops.last),
                const SizedBox(height: 14),
                AspectRatio(
                  key: const ValueKey('generic-route-map'),
                  aspectRatio: 1.65,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasCoordinates
                        ? _RouteMap(stops: stops)
                        : const _RouteMapUnavailable(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteOverviewCard extends StatelessWidget {
  const _RouteOverviewCard({
    required this.trip,
    required this.stages,
    required this.stageNavigationTargets,
    required this.onOpenTrip,
    required this.onOpenParentJourney,
    required this.personalContext,
  });

  final Trip trip;
  final List<Trip> stages;
  final List<Trip?> stageNavigationTargets;
  final ValueChanged<Trip> onOpenTrip;
  final VoidCallback? onOpenParentJourney;
  final Widget personalContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stops = _routeStops(trip, colorScheme);
    final segments = _routeSegmentMetrics(trip, stops, stages);
    final hasCoordinates =
        stops
            .where((stop) => stop.latitude != null && stop.longitude != null)
            .length >=
        2;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 8,
            color: colorScheme.primary,
            child: const CheckeredFlagStrip(height: 8),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < stops.length; index++) ...[
                  _RouteStopRow(stop: stops[index]),
                  if (index < stops.length - 1)
                    _RouteConnectionRow(
                      key: ValueKey('journey-stage-action-$index'),
                      from: stops[index],
                      to: stops[index + 1],
                      metrics: segments[index],
                      color: colorScheme.primary,
                      onTap:
                          stages.length > 1 &&
                              index < stageNavigationTargets.length &&
                              stageNavigationTargets[index] != null
                          ? () => onOpenTrip(stageNavigationTargets[index]!)
                          : null,
                    ),
                ],
                if (trip.isJourneyProjection) ...[
                  const SizedBox(height: 14),
                  _JourneyProjectionNotice(
                    trip: trip,
                    onOpenParentJourney: onOpenParentJourney,
                  ),
                ],
                const Divider(height: 24),
                InfoRow(
                  label: 'Inicio',
                  value: formatWeekdayDateTime(trip.startedAt),
                  compact: true,
                ),
                InfoRow(
                  label: 'Fin',
                  value: formatWeekdayDateTime(trip.endedAt),
                  compact: true,
                ),
                InfoRow(
                  label: 'Duración',
                  value: formatReadableDurationSeconds(trip.durationSeconds),
                  compact: true,
                ),
                InfoRow(
                  label: 'Velocidad',
                  value: formatSpeedKmh(trip.equivalentAverageSpeedKmh),
                  compact: true,
                ),
                InfoRow(
                  label: trip.hasMultipleBikes ? 'Bicicletas' : 'Bicicleta',
                  value: _formatBikeUsage(trip),
                  compact: true,
                ),
                InfoRow(
                  label: 'Precio',
                  value: formatDecimalEuros(trip.tripCost),
                  compact: true,
                ),
                const SizedBox(height: 14),
                AspectRatio(
                  aspectRatio: 1.65,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasCoordinates
                        ? _RouteMap(stops: stops)
                        : const _RouteMapUnavailable(),
                  ),
                ),
                const Divider(height: 32),
                personalContext,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyProjectionNotice extends StatelessWidget {
  const _JourneyProjectionNotice({
    required this.trip,
    required this.onOpenParentJourney,
  });

  final Trip trip;
  final VoidCallback? onOpenParentJourney;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSingleStage = trip.stageCount == 1;
    return DecoratedBox(
      key: const ValueKey('journey-projection-notice'),
      decoration: BoxDecoration(
        color: const Color(0xFF075E56).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF075E56).withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_gas_station_outlined,
                  color: Color(0xFF075E56),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSingleStage
                            ? 'Etapa de un viaje más largo'
                            : 'Tramo de ${trip.stageCount} etapas',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF075E56),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Forma parte de un viaje con más paradas.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('open-parent-journey-action'),
                onPressed: onOpenParentJourney,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.open_in_full, size: 17),
                label: const Text('Ver viaje completo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBikeUsage(Trip trip) {
  if (!trip.hasCompleteBikeData || trip.bikeIds.isEmpty) {
    return 'No disponible';
  }
  if (trip.bikeIds.length == 1) {
    return trip.bikeIds.single;
  }
  return trip.bikeIds.join(' · ');
}

class _TripPersonalContextSection extends StatelessWidget {
  const _TripPersonalContextSection({
    required this.trip,
    required this.routeTrips,
    required this.allTrips,
  });

  final Trip trip;
  final List<Trip> routeTrips;
  final List<Trip> allTrips;

  @override
  Widget build(BuildContext context) {
    final inverseTrips = allTrips.where(
      (candidate) => candidate.matchesRoute(
        originStationId: trip.destinationStationId,
        destinationStationId: trip.originStationId,
      ),
    );
    final orderedTrips = _rankTripsByDuration(routeTrips);
    final position = orderedTrips.indexWhere(
      (candidate) => candidate.id == trip.id,
    );

    return Column(
      key: const ValueKey('trip-personal-context-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.insights_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Tu historial en esta ruta',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PersonalRouteMetric(
                key: const ValueKey('personal-route-forward-action'),
                icon: Icons.directions_bike_outlined,
                value: '${routeTrips.length}',
                label: routeTrips.length == 1 ? 'Viaje' : 'Viajes',
                onTap: () => context.push(
                  _rankingsRouteLocation(
                    trip.originStationId,
                    trip.destinationStationId,
                  ),
                ),
              ),
            ),
            const _PersonalRouteMetricDivider(),
            Expanded(
              child: _PersonalRouteMetric(
                key: const ValueKey('personal-route-inverse-action'),
                icon: Icons.swap_horiz,
                value: '${inverseTrips.length}',
                label: 'Sentido inverso',
                onTap: () => context.push(
                  _rankingsRouteLocation(
                    trip.destinationStationId,
                    trip.originStationId,
                  ),
                ),
              ),
            ),
            const _PersonalRouteMetricDivider(),
            Expanded(
              child: _PersonalRouteMetric(
                icon: Icons.emoji_events_outlined,
                value: position < 0 ? '-' : '#${position + 1}',
                label: position < 0 ? 'Posición' : 'de ${orderedTrips.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => context.push(
            _rankingsRouteLocation(
              trip.originStationId,
              trip.destinationStationId,
            ),
          ),
          icon: const Icon(Icons.leaderboard_outlined),
          label: const Text('Ver en Rankings'),
        ),
      ],
    );
  }
}

class _TripContextLoadingSection extends StatelessWidget {
  const _TripContextLoadingSection();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 96,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _TripContextErrorSection extends StatelessWidget {
  const _TripContextErrorSection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('No se ha podido cargar el resumen personal.'),
    );
  }
}

class _PersonalRouteMetric extends StatelessWidget {
  const _PersonalRouteMetric({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 5),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _rankingsRouteLocation(String originStationId, String destinationId) {
  return '/route-history/'
      '${Uri.encodeComponent(originStationId)}/'
      '${Uri.encodeComponent(destinationId)}'
      '?view=rankings';
}

class _PersonalRouteMetricDivider extends StatelessWidget {
  const _PersonalRouteMetricDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: VerticalDivider(
        width: 12,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _RouteStop {
  const _RouteStop({
    required this.name,
    required this.kind,
    required this.color,
    this.latitude,
    this.longitude,
  });

  final String name;
  final _RouteStopKind kind;
  final Color color;
  final double? latitude;
  final double? longitude;
}

enum _RouteStopKind { origin, pitStop, destination }

List<_RouteStop> _routeStops(Trip trip, ColorScheme colorScheme) {
  final originIsIntermediate =
      trip.isJourneyProjection &&
      trip.originStationId != trip.parentJourneyOriginStationId;
  final destinationIsIntermediate =
      trip.isJourneyProjection &&
      trip.destinationStationId != trip.parentJourneyDestinationStationId;
  return [
    _RouteStop(
      name: trip.originStationName,
      kind: originIsIntermediate
          ? _RouteStopKind.pitStop
          : _RouteStopKind.origin,
      color: originIsIntermediate
          ? const Color(0xFF075E56)
          : colorScheme.primary,
      latitude: trip.originLatitude,
      longitude: trip.originLongitude,
    ),
    for (final pitStop in trip.pitStops)
      _RouteStop(
        name: pitStop.stationName,
        kind: _RouteStopKind.pitStop,
        color: const Color(0xFF075E56),
        latitude: pitStop.latitude,
        longitude: pitStop.longitude,
      ),
    _RouteStop(
      name: trip.destinationStationName,
      kind: destinationIsIntermediate
          ? _RouteStopKind.pitStop
          : _RouteStopKind.destination,
      color: destinationIsIntermediate ? const Color(0xFF075E56) : Colors.black,
      latitude: trip.destinationLatitude,
      longitude: trip.destinationLongitude,
    ),
  ];
}

List<_RouteStop> _genericRouteStops(Trip trip, ColorScheme colorScheme) {
  return [
    _RouteStop(
      name: trip.originStationName,
      kind: _RouteStopKind.origin,
      color: colorScheme.primary,
      latitude: trip.originLatitude,
      longitude: trip.originLongitude,
    ),
    _RouteStop(
      name: trip.destinationStationName,
      kind: _RouteStopKind.destination,
      color: Colors.black,
      latitude: trip.destinationLatitude,
      longitude: trip.destinationLongitude,
    ),
  ];
}

class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({required this.stop});

  final _RouteStop stop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoutePointMarker(stop: stop),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            stop.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _RouteConnectionRow extends StatelessWidget {
  const _RouteConnectionRow({
    required this.from,
    required this.to,
    required this.metrics,
    required this.color,
    this.onTap,
    super.key,
  });

  final _RouteStop from;
  final _RouteStop to;
  final _RouteSegmentMetrics metrics;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Icon(Icons.keyboard_arrow_down, color: color),
            ),
            Expanded(
              child: Text(
                '${formatDistanceMeters(metrics.distanceMeters)} · '
                '${_formatSegmentDuration(metrics.durationSeconds)} · '
                '${formatSpeedKmh(metrics.speedKmh)} · '
                '${formatDecimalEuros(metrics.tripCost)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _GenericRouteConnectionRow extends StatelessWidget {
  const _GenericRouteConnectionRow({
    required this.distanceMeters,
    required this.color,
  });

  final double? distanceMeters;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Icon(Icons.keyboard_arrow_down, color: color),
          ),
          Expanded(
            child: Text(
              formatDistanceMeters(distanceMeters),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSegmentMetrics {
  const _RouteSegmentMetrics({
    this.distanceMeters,
    this.durationSeconds,
    this.tripCost,
  });

  final double? distanceMeters;
  final int? durationSeconds;
  final String? tripCost;

  double? get speedKmh {
    final distance = distanceMeters;
    final duration = durationSeconds;
    if (distance == null || duration == null || duration <= 0) {
      return null;
    }
    return distance / duration * 3.6;
  }
}

List<Trip> _stagesForJourney(Trip journey, List<Trip> allStages) {
  final stageIds = journey.stageIds;
  if (stageIds.isEmpty) {
    return [journey];
  }
  final byId = {for (final stage in allStages) stage.id: stage};
  final stages = <Trip>[];
  for (final stageId in stageIds) {
    final stage = byId[stageId];
    if (stage == null) {
      return [journey];
    }
    stages.add(stage);
  }
  return stages;
}

List<Trip?> _stageNavigationTargets({
  required Trip selectedTrip,
  required List<Trip> stages,
  required List<Trip> rankingTrips,
}) {
  if (stages.length < 2) {
    return const [];
  }
  final parentJourneyId = selectedTrip.parentJourneyId ?? selectedTrip.id;
  return [
    for (final stage in stages)
      rankingTrips
          .where(
            (candidate) =>
                candidate.parentJourneyId == parentJourneyId &&
                candidate.stageIds.length == 1 &&
                candidate.stageIds.single == stage.id,
          )
          .firstOrNull,
  ];
}

String _tripDetailLocation(Trip trip) {
  return '/route-history/'
      '${Uri.encodeComponent(trip.originStationId)}/'
      '${Uri.encodeComponent(trip.destinationStationId)}'
      '?selectedTripId=${Uri.encodeQueryComponent(trip.id)}';
}

String _parentJourneyDetailLocation(Trip trip) {
  final parentId = trip.parentJourneyId;
  final originId = trip.parentJourneyOriginStationId;
  final destinationId = trip.parentJourneyDestinationStationId;
  if (parentId == null || originId == null || destinationId == null) {
    throw StateError('El viaje no tiene un viaje padre.');
  }
  return '/route-history/'
      '${Uri.encodeComponent(originId)}/'
      '${Uri.encodeComponent(destinationId)}'
      '?selectedTripId=${Uri.encodeQueryComponent(parentId)}';
}

List<_RouteSegmentMetrics> _routeSegmentMetrics(
  Trip trip,
  List<_RouteStop> stops,
  List<Trip> stages,
) {
  return [
    for (var index = 0; index < stops.length - 1; index++)
      () {
        final stage = stages.length == stops.length - 1
            ? stages[index]
            : stops.length == 2
            ? trip
            : null;
        final stageDetails = trip.stageDetails.length == stops.length - 1
            ? trip.stageDetails[index]
            : null;
        return _RouteSegmentMetrics(
          distanceMeters:
              stage?.directDistanceMeters ??
              _distanceBetween(stops[index], stops[index + 1]),
          durationSeconds: stage?.durationSeconds,
          tripCost: stage?.tripCost ?? stageDetails?.tripCost,
        );
      }(),
  ];
}

String _formatSegmentDuration(int? durationSeconds) {
  if (durationSeconds == null || durationSeconds <= 0) {
    return 'No disponible';
  }
  return formatDurationSeconds(durationSeconds);
}

double? _distanceBetween(_RouteStop from, _RouteStop to) {
  if (from.latitude == null ||
      from.longitude == null ||
      to.latitude == null ||
      to.longitude == null) {
    return null;
  }
  return haversineDistanceMeters(
    fromLatitude: from.latitude!,
    fromLongitude: from.longitude!,
    toLatitude: to.latitude!,
    toLongitude: to.longitude!,
  );
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.stops});

  final List<_RouteStop> stops;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final stop in stops)
        if (stop.latitude != null && stop.longitude != null)
          LatLng(stop.latitude!, stop.longitude!),
    ];
    final segments = _routeMapSegments(points);
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(36),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: CartoBasemapConfig.rasterTileUrlTemplate,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'bicimad_social',
        ),
        _DirectionalRouteLayer(segments: segments),
        MarkerLayer(
          markers: [
            for (final stop in stops)
              if (stop.latitude != null && stop.longitude != null)
                Marker(
                  point: LatLng(stop.latitude!, stop.longitude!),
                  width: 34,
                  height: 34,
                  child: _RoutePointMarker(stop: stop),
                ),
          ],
        ),
      ],
    );
  }
}

class _RouteMapSegment {
  const _RouteMapSegment({required this.from, required this.to});

  final LatLng from;
  final LatLng to;
}

List<_RouteMapSegment> _routeMapSegments(List<LatLng> points) {
  return [
    for (var index = 0; index < points.length - 1; index++)
      _RouteMapSegment(from: points[index], to: points[index + 1]),
  ];
}

class _DirectionalRouteLayer extends StatelessWidget {
  const _DirectionalRouteLayer({required this.segments});

  final List<_RouteMapSegment> segments;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _DirectionalRoutePainter(
            segments: [
              for (final segment in segments)
                (
                  from: camera.latLngToScreenOffset(segment.from),
                  to: camera.latLngToScreenOffset(segment.to),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionalRoutePainter extends CustomPainter {
  const _DirectionalRoutePainter({required this.segments});

  final List<({Offset from, Offset to})> segments;

  static const markerRadius = 17.0;
  static const arrowLength = 11.0;
  static const arrowHalfWidth = 5.5;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final segment in segments) {
      final delta = segment.to - segment.from;
      final distance = delta.distance;
      if (distance <= markerRadius * 2 + arrowLength) continue;

      final direction = delta / distance;
      final perpendicular = Offset(-direction.dy, direction.dx);
      final start = segment.from + direction * markerRadius;
      final tip = segment.to - direction * markerRadius;
      final arrowBase = tip - direction * arrowLength;
      final lineEnd = arrowBase + direction * 2;

      canvas.drawLine(start, lineEnd, linePaint);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            arrowBase.dx + perpendicular.dx * arrowHalfWidth,
            arrowBase.dy + perpendicular.dy * arrowHalfWidth,
          )
          ..lineTo(
            arrowBase.dx - perpendicular.dx * arrowHalfWidth,
            arrowBase.dy - perpendicular.dy * arrowHalfWidth,
          )
          ..close(),
        arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DirectionalRoutePainter oldDelegate) {
    return oldDelegate.segments != segments;
  }
}

class _RoutePointMarker extends StatelessWidget {
  const _RoutePointMarker({required this.stop});

  final _RouteStop stop;

  @override
  Widget build(BuildContext context) {
    if (stop.kind == _RouteStopKind.destination) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: _CheckeredDestinationMarker(),
      );
    }

    return SizedBox(
      key: stop.kind == _RouteStopKind.pitStop
          ? const ValueKey('route-pit-stop-marker')
          : null,
      width: 34,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: stop.color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: stop.kind == _RouteStopKind.origin
              ? const DockingStationIcon(
                  key: ValueKey('route-origin-dock-icon'),
                  color: Colors.white,
                  width: 15,
                  height: 16,
                )
              : const Icon(
                  Icons.local_gas_station_outlined,
                  color: Colors.white,
                  size: 18,
                ),
        ),
      ),
    );
  }
}

class _CheckeredDestinationMarker extends StatelessWidget {
  const _CheckeredDestinationMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('route-destination-checkered-marker'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: ClipOval(
          child: CustomPaint(painter: _CheckeredDestinationPainter()),
        ),
      ),
    );
  }
}

class _CheckeredDestinationPainter extends CustomPainter {
  const _CheckeredDestinationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 4;
    final cellWidth = size.width / cells;
    final cellHeight = size.height / cells;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var row = 0; row < cells; row++) {
      for (var column = 0; column < cells; column++) {
        paint.color = (row + column).isEven ? Colors.white : Colors.black;
        canvas.drawRect(
          Rect.fromLTWH(
            column * cellWidth,
            row * cellHeight,
            cellWidth,
            cellHeight,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckeredDestinationPainter oldDelegate) {
    return false;
  }
}

class _RouteMapUnavailable extends StatelessWidget {
  const _RouteMapUnavailable();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Center(child: Text('Mapa no disponible para esta ruta.')),
    );
  }
}

enum _RouteRankingViewMode { personal, community }

class _LegacyHistorySection extends ConsumerStatefulWidget {
  const _LegacyHistorySection({
    required this.routeKey,
    required this.modelAsync,
    required this.personalTrips,
    required this.personalStatistics,
    required this.avatarAsset,
    this.onTripSelected,
    this.startInCommunity = false,
  });

  final RouteKey routeKey;
  final AsyncValue<LegacyRouteModel?> modelAsync;
  final List<Trip> personalTrips;
  final RouteStatistics personalStatistics;
  final String avatarAsset;
  final ValueChanged<Trip>? onTripSelected;
  final bool startInCommunity;

  @override
  ConsumerState<_LegacyHistorySection> createState() =>
      _LegacyHistorySectionState();
}

class _LegacyHistorySectionState extends ConsumerState<_LegacyHistorySection> {
  late _RouteRankingViewMode _mode = widget.startInCommunity
      ? _RouteRankingViewMode.community
      : _RouteRankingViewMode.personal;
  String? _selectedPersonalTripId;
  String? _selectedCommunityUserId;

  @override
  Widget build(BuildContext context) {
    final currentProfile = ref.watch(currentSocialProfileProvider);
    final currentDisplayName =
        currentProfile?.displayName ??
        ref.watch(currentDisplayNameProvider) ??
        '\u0054\u00FA';
    final communityRankingAsync = _mode == _RouteRankingViewMode.community
        ? ref.watch(routeCommunityRankingProvider(widget.routeKey))
        : const AsyncData<CommunityRouteRanking>(
            CommunityRouteRanking(entries: []),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteRankingModeSelector(
          mode: _mode,
          onChanged: (mode) => setState(() {
            _mode = mode;
            _selectedPersonalTripId = null;
            _selectedCommunityUserId = null;
          }),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mode == _RouteRankingViewMode.personal
                      ? 'Mis viajes vs Histórico usuarios BiciMAD'
                      : 'Comunidad vs Histórico usuarios BiciMAD',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                widget.modelAsync.when(
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => const Text(
                    'No se ha podido leer el historico comparable.',
                  ),
                  data: (model) {
                    final rankedTrips = _rankTripsByDuration(
                      widget.personalTrips,
                    );
                    final hasHistoricalCurve = model?.canPlot == true;
                    final chartRange = _routeChartRange(
                      model,
                      rankedTrips.map(
                        (trip) => trip.durationSeconds.toDouble(),
                      ),
                    );
                    final selectedPersonalTrip = rankedTrips
                        .where((trip) => trip.id == _selectedPersonalTripId)
                        .firstOrNull;
                    if (_mode == _RouteRankingViewMode.community) {
                      return communityRankingAsync.when(
                        loading: () => _CommunityChartLoading(
                          model: model,
                          fallbackDurations: [
                            for (final trip in rankedTrips)
                              trip.durationSeconds.toDouble(),
                          ],
                        ),
                        error: (error, stackTrace) => _CommunityChartError(
                          model: model,
                          fallbackDurations: [
                            for (final trip in rankedTrips)
                              trip.durationSeconds.toDouble(),
                          ],
                          onRetry: () => ref.invalidate(
                            routeCommunityRankingProvider(widget.routeKey),
                          ),
                        ),
                        data: (ranking) => _CommunityChartContent(
                          model: model,
                          ranking: ranking,
                          selectedUserId: _selectedCommunityUserId,
                          onUserSelected: (userId) => setState(() {
                            _selectedCommunityUserId =
                                _selectedCommunityUserId == userId
                                ? null
                                : userId;
                          }),
                        ),
                      );
                    }

                    return TapRegion(
                      onTapOutside: selectedPersonalTrip == null
                          ? null
                          : (_) =>
                                setState(() => _selectedPersonalTripId = null),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!hasHistoricalCurve) ...[
                            const Text(
                              'No hay suficiente historico comparable para esta ruta.',
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            key: const ValueKey('route-duration-chart'),
                            height: 216,
                            width: double.infinity,
                            child: _LegacyDurationChart(
                              painter: _LegacyCurvePainter(
                                points: hasHistoricalCurve
                                    ? model!.smoothedDensityPoints()
                                    : const [],
                                personalDurations: [
                                  for (final trip in rankedTrips)
                                    trip.durationSeconds.toDouble(),
                                ],
                                rangeStart: chartRange.start,
                                rangeEnd: chartRange.end,
                                colorScheme: Theme.of(context).colorScheme,
                              ),
                              trips: rankedTrips,
                              avatarAsset: widget.avatarAsset,
                              rangeEnd: chartRange.end,
                              selectedTripId: _selectedPersonalTripId,
                              onTripSelected: (tripId) => setState(() {
                                _selectedPersonalTripId =
                                    _selectedPersonalTripId == tripId
                                    ? null
                                    : tripId;
                              }),
                            ),
                          ),
                          if (selectedPersonalTrip != null) ...[
                            const SizedBox(height: 8),
                            _PersonalMarkerCallout(
                              trip: selectedPersonalTrip,
                              position:
                                  rankedTrips.indexOf(selectedPersonalTrip) + 1,
                              historicalModel: model,
                              avatarAsset: widget.avatarAsset,
                              displayName: currentDisplayName,
                              username: currentProfile?.username,
                            ),
                          ],
                          const SizedBox(height: 16),
                          _RouteHistoryComparison(
                            historicalModel: model,
                            comparisonTitle: 'MIS VIAJES',
                            comparisonTripCount:
                                widget.personalStatistics.totalTrips,
                            comparisonBestSeconds:
                                widget.personalStatistics.bestDurationSeconds,
                            comparisonTypicalSeconds:
                                widget.personalStatistics.medianDurationSeconds,
                            comparisonLeading: ProfileAvatar(
                              key: const ValueKey('personal-comparison-avatar'),
                              assetPath: widget.avatarAsset,
                              radius: 10,
                              isSelected: false,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_mode == _RouteRankingViewMode.personal)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _PersonalTripsSection(
                trips: widget.personalTrips,
                avatarAsset: widget.avatarAsset,
                displayName: currentDisplayName,
                username: currentProfile?.username,
                historicalModel: widget.modelAsync.valueOrNull,
                onTripSelected: widget.onTripSelected,
              ),
            ),
          )
        else
          _CommunityTripsCard(
            rankingAsync: communityRankingAsync,
            historicalModel: widget.modelAsync.valueOrNull,
            personalTrips: widget.personalTrips,
            onTripSelected: widget.onTripSelected,
            onRetry: () =>
                ref.invalidate(routeCommunityRankingProvider(widget.routeKey)),
          ),
      ],
    );
  }
}

class _RouteRankingModeSelector extends StatelessWidget {
  const _RouteRankingModeSelector({
    required this.mode,
    required this.onChanged,
  });

  final _RouteRankingViewMode mode;
  final ValueChanged<_RouteRankingViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_RouteRankingViewMode>(
      key: const ValueKey('route-ranking-mode-selector'),
      segments: const [
        ButtonSegment(
          value: _RouteRankingViewMode.personal,
          label: Text('Mis viajes'),
          icon: Icon(Icons.directions_bike_outlined),
        ),
        ButtonSegment(
          value: _RouteRankingViewMode.community,
          label: Text('Comunidad'),
          icon: Icon(Icons.people_outline),
        ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

typedef _DurationViewportBuilder =
    Widget Function(
      BuildContext context,
      double visibleStart,
      double visibleEnd,
      bool isFullRange,
    );

class _HorizontalDurationViewport extends StatefulWidget {
  const _HorizontalDurationViewport({
    required this.fullRangeEnd,
    required this.builder,
  });

  final double fullRangeEnd;
  final _DurationViewportBuilder builder;

  @override
  State<_HorizontalDurationViewport> createState() =>
      _HorizontalDurationViewportState();
}

class _HorizontalDurationViewportState
    extends State<_HorizontalDurationViewport> {
  double _zoom = 1;
  double _visibleStart = 0;
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartZoom = 1;
  double _pinchAnchorSeconds = 0;

  double get _fullRangeEnd =>
      widget.fullRangeEnd.isFinite && widget.fullRangeEnd > 0
      ? widget.fullRangeEnd
      : 60;

  double get _visibleSpan => _fullRangeEnd / _zoom;
  double get _maxZoom => (_fullRangeEnd / 5).clamp(1.0, 12.0);

  @override
  void didUpdateWidget(covariant _HorizontalDurationViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullRangeEnd != widget.fullRangeEnd) {
      _zoom = 1;
      _visibleStart = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final visibleEnd = _visibleStart + _visibleSpan;
              final isFullRange = _zoom <= 1.0001;
              return Semantics(
                key: const ValueKey('duration-chart-zoom-viewport'),
                label: 'Gráfico de duración ampliable en horizontal',
                value:
                    '${_visibleStart.round()}-${visibleEnd.round()} segundos',
                child: Listener(
                  onPointerDown: (event) =>
                      _handlePointerDown(event, constraints.maxWidth),
                  onPointerMove: (event) =>
                      _handlePointerMove(event, constraints.maxWidth),
                  onPointerUp: _handlePointerEnd,
                  onPointerCancel: _handlePointerEnd,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      if (_pointers.length > 1) return;
                      final chartWidth =
                          constraints.maxWidth -
                          _legacyChartLeft -
                          _legacyChartRight;
                      if (chartWidth <= 0 || _zoom <= 1.0001) return;
                      _applyViewport(
                        zoom: _zoom,
                        start:
                            _visibleStart -
                            details.delta.dx * _visibleSpan / chartWidth,
                      );
                    },
                    child: widget.builder(
                      context,
                      _visibleStart,
                      visibleEnd,
                      isFullRange,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _DurationChartControl(
                key: const ValueKey('duration-chart-zoom-out'),
                tooltip: 'Alejar',
                icon: Icons.zoom_out,
                onPressed: _zoom <= 1.0001 ? null : () => _zoomBy(1 / 1.5),
              ),
              _DurationChartControl(
                key: const ValueKey('duration-chart-zoom-in'),
                tooltip: 'Ampliar',
                icon: Icons.zoom_in,
                onPressed: _zoom >= _maxZoom ? null : () => _zoomBy(1.5),
              ),
              _DurationChartControl(
                key: const ValueKey('duration-chart-zoom-reset'),
                tooltip: 'Ver rango completo',
                icon: Icons.fit_screen,
                onPressed: _zoom <= 1.0001 ? null : _reset,
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _focalFraction(double localX, double width) {
    final chartWidth = width - _legacyChartLeft - _legacyChartRight;
    if (chartWidth <= 0) return 0.5;
    return ((localX - _legacyChartLeft) / chartWidth).clamp(0.0, 1.0);
  }

  void _handlePointerDown(PointerDownEvent event, double width) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _beginPinch(width);
    }
  }

  void _handlePointerMove(PointerMoveEvent event, double width) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final startDistance = _pinchStartDistance;
    if (_pointers.length != 2 || startDistance == null || startDistance <= 0) {
      return;
    }
    final points = _pointers.values.toList(growable: false);
    final currentDistance = (points.first - points.last).distance;
    final nextZoom = (_pinchStartZoom * currentDistance / startDistance).clamp(
      1.0,
      _maxZoom,
    );
    final nextSpan = _fullRangeEnd / nextZoom;
    final midpointX = (points.first.dx + points.last.dx) / 2;
    final fraction = _focalFraction(midpointX, width);
    _applyViewport(
      zoom: nextZoom,
      start: _pinchAnchorSeconds - fraction * nextSpan,
    );
  }

  void _handlePointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    _pinchStartDistance = null;
  }

  void _beginPinch(double width) {
    final points = _pointers.values.toList(growable: false);
    _pinchStartDistance = (points.first - points.last).distance;
    _pinchStartZoom = _zoom;
    final midpointX = (points.first.dx + points.last.dx) / 2;
    _pinchAnchorSeconds =
        _visibleStart + _focalFraction(midpointX, width) * _visibleSpan;
  }

  void _zoomBy(double factor) {
    final anchor = _visibleStart + _visibleSpan / 2;
    final nextZoom = (_zoom * factor).clamp(1.0, _maxZoom);
    final nextSpan = _fullRangeEnd / nextZoom;
    _applyViewport(zoom: nextZoom, start: anchor - nextSpan / 2);
  }

  void _applyViewport({required double zoom, required double start}) {
    final nextSpan = _fullRangeEnd / zoom;
    final maxStart = _fullRangeEnd - nextSpan;
    final nextStart = start.clamp(0.0, maxStart);
    if ((zoom - _zoom).abs() < 0.0001 &&
        (nextStart - _visibleStart).abs() < 0.0001) {
      return;
    }
    setState(() {
      _zoom = zoom;
      _visibleStart = nextStart;
    });
  }

  void _reset() {
    if (_zoom <= 1.0001 && _visibleStart == 0) return;
    setState(() {
      _zoom = 1;
      _visibleStart = 0;
    });
  }
}

class _DurationChartControl extends StatelessWidget {
  const _DurationChartControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 32),
      padding: EdgeInsets.zero,
    );
  }
}

class _LegacyDurationChart extends StatelessWidget {
  const _LegacyDurationChart({
    required this.painter,
    required this.trips,
    required this.avatarAsset,
    required this.rangeEnd,
    required this.selectedTripId,
    required this.onTripSelected,
  });

  final _LegacyCurvePainter painter;
  final List<Trip> trips;
  final String avatarAsset;
  final double rangeEnd;
  final String? selectedTripId;
  final ValueChanged<String> onTripSelected;

  @override
  Widget build(BuildContext context) {
    final avatarTrips = trips.asMap().entries.toList(growable: false).reversed;
    return _HorizontalDurationViewport(
      fullRangeEnd: rangeEnd,
      builder: (context, visibleStart, visibleEnd, isFullRange) =>
          LayoutBuilder(
            builder: (context, constraints) {
              final chartRight = constraints.maxWidth - _legacyChartRight;
              final chartWidth = chartRight - _legacyChartLeft;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: painter.withViewport(
                        rangeStart: visibleStart,
                        rangeEnd: visibleEnd,
                        showUpperOutliers: isFullRange,
                      ),
                    ),
                  ),
                  if (chartWidth > 0 && visibleEnd > visibleStart)
                    for (final rankedTrip in avatarTrips)
                      if (_durationIsVisible(
                        rankedTrip.value.durationSeconds.toDouble(),
                        visibleStart: visibleStart,
                        visibleEnd: visibleEnd,
                        fullRangeEnd: rangeEnd,
                        showUpperOutliers: isFullRange,
                      ))
                        Positioned(
                          key: ValueKey(
                            'legacy-chart-avatar-${rankedTrip.value.id}',
                          ),
                          left:
                              (_markerX(
                                        rankedTrip.value.durationSeconds
                                            .toDouble(),
                                        visibleStart,
                                        visibleEnd,
                                        chartWidth,
                                        chartRight,
                                      ) -
                                      14)
                                  .clamp(0, constraints.maxWidth - 28),
                          top: 0,
                          child: _PersonalChartAvatar(
                            avatarAsset: avatarAsset,
                            position: rankedTrip.key + 1,
                            isSelected: selectedTripId == rankedTrip.value.id,
                            onTap: () => onTripSelected(rankedTrip.value.id),
                          ),
                        ),
                ],
              );
            },
          ),
    );
  }

  double _markerX(
    double duration,
    double visibleStart,
    double visibleEnd,
    double chartWidth,
    double chartRight,
  ) {
    if (duration > visibleEnd) return chartRight;
    return _legacyChartLeft +
        ((duration - visibleStart) / (visibleEnd - visibleStart)) * chartWidth;
  }
}

bool _durationIsVisible(
  double duration, {
  required double visibleStart,
  required double visibleEnd,
  required double fullRangeEnd,
  required bool showUpperOutliers,
}) {
  if (duration < visibleStart) return false;
  if (duration <= visibleEnd) return true;
  return showUpperOutliers && duration > fullRangeEnd;
}

class _PersonalChartAvatar extends StatelessWidget {
  const _PersonalChartAvatar({
    required this.avatarAsset,
    required this.position,
    required this.isSelected,
    required this.onTap,
  });

  final String avatarAsset;
  final int position;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Ver mi viaje en posición $position',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: _RankedChartAvatarFrame(
          key: ValueKey('personal-chart-rank-frame-$position'),
          assetPath: avatarAsset,
          rank: position,
        ),
      ),
    );
  }
}

class _PersonalMarkerCallout extends StatelessWidget {
  const _PersonalMarkerCallout({
    required this.trip,
    required this.position,
    required this.historicalModel,
    required this.avatarAsset,
    required this.displayName,
    required this.username,
  });

  final Trip trip;
  final int position;
  final LegacyRouteModel? historicalModel;
  final String avatarAsset;
  final String displayName;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percentile = historicalModel?.canPlot == true
        ? historicalModel!.percentileForDuration(
            trip.durationSeconds.toDouble(),
          )
        : null;
    final percentileLabel = percentile == null
        ? 'P--'
        : 'P${percentile.clamp(0, 100).round()}';
    return DecoratedBox(
      key: ValueKey('personal-marker-callout-${trip.id}'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ProfileAvatar(assetPath: avatarAsset, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const _YouBadge(),
                    ],
                  ),
                  if (username?.trim().isNotEmpty == true)
                    Text(
                      '@${username!.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$position.\u00BA \u00B7 '
                  '${formatDurationSeconds(trip.durationSeconds)} \u00B7 '
                  '$percentileLabel',
                  key: ValueKey('personal-marker-summary-${trip.id}'),
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  formatSpeedKmh(trip.equivalentAverageSpeedKmh),
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _legacyChartLeft = 42.0;
const _legacyChartTop = 26.0;
const _legacyChartRight = 8.0;
const _legacyChartBottom = 28.0;

({double start, double end}) _routeChartRange(
  LegacyRouteModel? model,
  Iterable<double> durations,
) {
  if (model != null &&
      model.bestSeconds.isFinite &&
      model.upperCutoffSeconds.isFinite &&
      model.upperCutoffSeconds > model.bestSeconds) {
    return (start: 0, end: model.upperCutoffSeconds);
  }

  final values =
      durations
          .where((value) => value.isFinite && value > 0)
          .toList(growable: false)
        ..sort();
  if (values.isEmpty) {
    return (start: 0, end: 60);
  }

  final maximum = values.last;
  final spread = maximum - values.first;
  final proportionalPadding = spread > 0 ? spread * 0.12 : maximum * 0.15;
  final padding = proportionalPadding < 15 ? 15.0 : proportionalPadding;
  return (start: 0, end: maximum + padding);
}

class _LegacyCurvePainter extends CustomPainter {
  const _LegacyCurvePainter({
    required this.points,
    required this.personalDurations,
    required this.rangeStart,
    required this.rangeEnd,
    required this.colorScheme,
    this.markerPositions,
    this.showUpperOutliers = true,
  });

  final List<HistogramPoint> points;
  final List<double> personalDurations;
  final double rangeStart;
  final double rangeEnd;
  final ColorScheme colorScheme;
  final List<int>? markerPositions;
  final bool showUpperOutliers;

  _LegacyCurvePainter withViewport({
    required double rangeStart,
    required double rangeEnd,
    required bool showUpperOutliers,
  }) {
    return _LegacyCurvePainter(
      points: points,
      personalDurations: personalDurations,
      markerPositions: markerPositions,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      colorScheme: colorScheme,
      showUpperOutliers: showUpperOutliers,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(
      _legacyChartLeft,
      _legacyChartTop,
      size.width - _legacyChartRight,
      size.height - _legacyChartBottom,
    );
    if (chart.width <= 0 || chart.height <= 0 || rangeEnd <= rangeStart) {
      return;
    }

    final axisPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.bottomLeft, chart.topLeft, axisPaint);

    final maxDensity = points.fold<double>(
      0,
      (max, point) => point.density > max ? point.density : max,
    );
    canvas.save();
    canvas.clipRect(chart);
    if (maxDensity > 0) {
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final point = points[index];
        final x = _mapX(point.seconds, chart);
        final y = chart.bottom - (point.density / maxDensity) * chart.height;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colorScheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    for (var index = personalDurations.length - 1; index >= 0; index--) {
      final duration = personalDurations[index];
      if (duration < rangeStart) continue;
      if (duration > rangeEnd && !showUpperOutliers) continue;
      final x = duration > rangeEnd ? chart.right : _mapX(duration, chart);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.top),
        Paint()
          ..color = tripRankAccentColor(
            markerPositions == null ? index + 1 : markerPositions![index],
          )
          ..strokeWidth = (markerPositions?[index] ?? index + 1) <= 3
              ? 2.5
              : 1.2,
      );
    }
    canvas.restore();

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final tick in durationAxisTicks(rangeStart, rangeEnd)) {
      final x = _mapX(tick, chart);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.bottom + 4),
        axisPaint,
      );
      _paintAxisLabel(canvas, textPainter, tick, chart);
    }
  }

  @override
  bool shouldRepaint(covariant _LegacyCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.personalDurations != personalDurations ||
        oldDelegate.markerPositions != markerPositions ||
        oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd ||
        oldDelegate.showUpperOutliers != showUpperOutliers;
  }

  double _mapX(double seconds, Rect chart) {
    return chart.left +
        ((seconds - rangeStart) / (rangeEnd - rangeStart)) * chart.width;
  }

  void _paintAxisLabel(
    Canvas canvas,
    TextPainter textPainter,
    double seconds,
    Rect chart,
  ) {
    textPainter
      ..text = TextSpan(
        text: formatDurationAxisTick(seconds),
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
      )
      ..layout(maxWidth: 64);
    final tickX = _mapX(seconds, chart);
    final labelX = (tickX - textPainter.width / 2)
        .clamp(chart.left, chart.right - textPainter.width)
        .toDouble();
    textPainter.paint(canvas, Offset(labelX, chart.bottom + 7));
  }
}

class _CommunityChartLoading extends StatelessWidget {
  const _CommunityChartLoading({
    required this.model,
    required this.fallbackDurations,
  });

  final LegacyRouteModel? model;
  final List<double> fallbackDurations;

  @override
  Widget build(BuildContext context) {
    final chartRange = _routeChartRange(model, fallbackDurations);
    final hasHistoricalCurve = model?.canPlot == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasHistoricalCurve) ...[
          const Text('No hay suficiente historico comparable para esta ruta.'),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 216,
          width: double.infinity,
          child: _HorizontalDurationViewport(
            fullRangeEnd: chartRange.end,
            builder: (context, visibleStart, visibleEnd, isFullRange) =>
                CustomPaint(
                  painter: _LegacyCurvePainter(
                    points: hasHistoricalCurve
                        ? model!.smoothedDensityPoints()
                        : const [],
                    personalDurations: const [],
                    rangeStart: visibleStart,
                    rangeEnd: visibleEnd,
                    colorScheme: Theme.of(context).colorScheme,
                    showUpperOutliers: isFullRange,
                  ),
                ),
          ),
        ),
        const LinearProgressIndicator(
          key: ValueKey('community-route-ranking-loading'),
        ),
      ],
    );
  }
}

class _CommunityChartError extends StatelessWidget {
  const _CommunityChartError({
    required this.model,
    required this.fallbackDurations,
    required this.onRetry,
  });

  final LegacyRouteModel? model;
  final List<double> fallbackDurations;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final chartRange = _routeChartRange(model, fallbackDurations);
    final hasHistoricalCurve = model?.canPlot == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasHistoricalCurve) ...[
          const Text('No hay suficiente historico comparable para esta ruta.'),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 216,
          width: double.infinity,
          child: _HorizontalDurationViewport(
            fullRangeEnd: chartRange.end,
            builder: (context, visibleStart, visibleEnd, isFullRange) =>
                CustomPaint(
                  painter: _LegacyCurvePainter(
                    points: hasHistoricalCurve
                        ? model!.smoothedDensityPoints()
                        : const [],
                    personalDurations: const [],
                    rangeStart: visibleStart,
                    rangeEnd: visibleEnd,
                    colorScheme: Theme.of(context).colorScheme,
                    showUpperOutliers: isFullRange,
                  ),
                ),
          ),
        ),
        const Text('No se ha podido cargar el ranking de Comunidad.'),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}

class _CommunityChartContent extends StatelessWidget {
  const _CommunityChartContent({
    required this.model,
    required this.ranking,
    required this.selectedUserId,
    required this.onUserSelected,
  });

  final LegacyRouteModel? model;
  final CommunityRouteRanking ranking;
  final String? selectedUserId;
  final ValueChanged<String> onUserSelected;

  @override
  Widget build(BuildContext context) {
    final selectedEntry = ranking.entries
        .where((entry) => entry.userId == selectedUserId)
        .firstOrNull;
    final bestEntry = ranking.entries.firstOrNull;
    final ownEntry = ranking.currentUserEntry;
    final hasHistoricalCurve = model?.canPlot == true;

    return TapRegion(
      onTapOutside: selectedEntry == null
          ? null
          : (_) => onUserSelected(selectedEntry.userId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            key: const ValueKey('community-duration-chart'),
            height: 216,
            width: double.infinity,
            child: _CommunityDurationChart(
              model: model,
              entries: ranking.entries,
              showHistoricalCurve:
                  hasHistoricalCurve && ranking.entries.isNotEmpty,
              onUserSelected: onUserSelected,
            ),
          ),
          if (selectedEntry != null) ...[
            const SizedBox(height: 8),
            _CommunityMarkerCallout(
              entry: selectedEntry,
              historicalModel: model,
            ),
          ],
          if (!hasHistoricalCurve || ranking.entries.isEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'No hay suficiente historico comparable para esta ruta.',
              key: ValueKey('community-route-empty-chart'),
            ),
          ],
          const SizedBox(height: 16),
          _RouteHistoryComparison(
            historicalModel: model,
            comparisonTitle: 'COMUNIDAD',
            comparisonTripCount: ranking.entries.length,
            comparisonBestSeconds: bestEntry?.durationSeconds,
            comparisonTypicalSeconds: ownEntry?.durationSeconds,
            comparisonLeading: Icon(
              Icons.people_outline,
              size: 19,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            comparisonCountLabel: 'Usuarios',
            comparisonTypicalLabel: 'Mi mejor',
            comparisonBestValueLeading: bestEntry == null
                ? null
                : _ComparisonUserMarker(entry: bestEntry),
            comparisonTypicalValueLeading: ownEntry == null
                ? null
                : _ComparisonUserMarker(entry: ownEntry),
          ),
        ],
      ),
    );
  }
}

class _CommunityDurationChart extends StatelessWidget {
  const _CommunityDurationChart({
    required this.model,
    required this.entries,
    required this.showHistoricalCurve,
    required this.onUserSelected,
  });

  final LegacyRouteModel? model;
  final List<CommunityRouteRankingEntry> entries;
  final bool showHistoricalCurve;
  final ValueChanged<String> onUserSelected;

  @override
  Widget build(BuildContext context) {
    final chartRange = _routeChartRange(
      model,
      entries.map((entry) => entry.durationSeconds),
    );
    return _HorizontalDurationViewport(
      fullRangeEnd: chartRange.end,
      builder: (context, visibleStart, visibleEnd, isFullRange) =>
          LayoutBuilder(
            builder: (context, constraints) {
              final chartRight = constraints.maxWidth - _legacyChartRight;
              final chartWidth = chartRight - _legacyChartLeft;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LegacyCurvePainter(
                        points: showHistoricalCurve
                            ? model!.smoothedDensityPoints()
                            : const [],
                        personalDurations: [
                          for (final entry in entries) entry.durationSeconds,
                        ],
                        markerPositions: [
                          for (final entry in entries) entry.position,
                        ],
                        rangeStart: visibleStart,
                        rangeEnd: visibleEnd,
                        colorScheme: Theme.of(context).colorScheme,
                        showUpperOutliers: isFullRange,
                      ),
                    ),
                  ),
                  if (chartWidth > 0)
                    for (final entry in entries.reversed)
                      if (_durationIsVisible(
                        entry.durationSeconds,
                        visibleStart: visibleStart,
                        visibleEnd: visibleEnd,
                        fullRangeEnd: chartRange.end,
                        showUpperOutliers: isFullRange,
                      ))
                        Positioned(
                          key: ValueKey(
                            'community-chart-avatar-${entry.userId}',
                          ),
                          left:
                              (_communityMarkerX(
                                        entry.durationSeconds,
                                        visibleStart,
                                        visibleEnd,
                                        chartWidth,
                                        chartRight,
                                      ) -
                                      14)
                                  .clamp(0, constraints.maxWidth - 28),
                          top: 0,
                          child: _CommunityChartAvatar(
                            entry: entry,
                            onTap: () => onUserSelected(entry.userId),
                          ),
                        ),
                ],
              );
            },
          ),
    );
  }
}

double _communityMarkerX(
  double duration,
  double rangeStart,
  double rangeEnd,
  double chartWidth,
  double chartRight,
) {
  if (duration > rangeEnd) return chartRight;
  return _legacyChartLeft +
      ((duration - rangeStart) / (rangeEnd - rangeStart)) * chartWidth;
}

class _CommunityChartAvatar extends StatelessWidget {
  const _CommunityChartAvatar({required this.entry, required this.onTap});

  final CommunityRouteRankingEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ver resultado de ${entry.displayName}',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _RankedChartAvatarFrame(
              key: ValueKey('community-chart-rank-frame-${entry.userId}'),
              assetPath: entry.avatarAsset,
              rank: entry.position,
            ),
            if (entry.isCurrentUser)
              Positioned(top: 23, left: -3, child: _YouBadge(compact: true)),
          ],
        ),
      ),
    );
  }
}

class _RankedChartAvatarFrame extends StatelessWidget {
  const _RankedChartAvatarFrame({
    required this.assetPath,
    required this.rank,
    super.key,
  });

  final String assetPath;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final hasRankBorder = rank <= 3;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: hasRankBorder
            ? Border.all(color: tripRankAccentColor(rank), width: 2.5)
            : null,
        color: hasRankBorder ? Theme.of(context).colorScheme.surface : null,
      ),
      padding: EdgeInsets.all(hasRankBorder ? 1 : 3.5),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            LocalAvatarRepository.defaultAvatarAsset,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _CommunityMarkerCallout extends StatelessWidget {
  const _CommunityMarkerCallout({
    required this.entry,
    required this.historicalModel,
  });

  final CommunityRouteRankingEntry entry;
  final LegacyRouteModel? historicalModel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percentile = historicalModel?.canPlot == true
        ? historicalModel!.percentileForDuration(entry.durationSeconds)
        : null;
    final percentileLabel = percentile == null
        ? 'P--'
        : 'P${percentile.clamp(0, 100).round()}';
    return DecoratedBox(
      key: ValueKey('community-marker-callout-${entry.userId}'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ProfileAvatar(
              assetPath: entry.avatarAsset,
              radius: 18,
              isSelected: false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (entry.isCurrentUser) ...[
                        const SizedBox(width: 6),
                        const _YouBadge(),
                      ],
                    ],
                  ),
                  Text(
                    '@${entry.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${entry.position}.\u00BA \u00B7 '
                  '${_formatCommunityDuration(entry.durationMilliseconds)} '
                  '\u00B7 $percentileLabel',
                  key: ValueKey('community-marker-summary-${entry.userId}'),
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  formatSpeedKmh(entry.equivalentAverageSpeedKmh),
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _YouBadge extends StatelessWidget {
  const _YouBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: compact ? const ValueKey('community-chart-you-badge') : null,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 1 : 2,
        ),
        child: Text(
          'Tú',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontSize: compact ? 8 : 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ComparisonUserMarker extends StatelessWidget {
  const _ComparisonUserMarker({required this.entry});

  final CommunityRouteRankingEntry entry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('comparison-user-marker-${entry.userId}'),
      width: entry.isCurrentUser ? 28 : 20,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProfileAvatar(
            assetPath: entry.avatarAsset,
            radius: 9,
            isSelected: false,
          ),
          if (entry.isCurrentUser)
            const Positioned(
              left: 12,
              top: 13,
              child: _YouBadge(compact: true),
            ),
        ],
      ),
    );
  }
}

String _formatCommunityDuration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final remainderMilliseconds = milliseconds.remainder(1000);
  final base = formatDurationSeconds(totalSeconds);
  if (remainderMilliseconds == 0) return base;
  return '$base.${remainderMilliseconds.toString().padLeft(3, '0')}';
}

class _RouteHistoryComparison extends StatelessWidget {
  const _RouteHistoryComparison({
    required this.historicalModel,
    required this.comparisonTitle,
    required this.comparisonTripCount,
    required this.comparisonBestSeconds,
    required this.comparisonTypicalSeconds,
    required this.comparisonLeading,
    this.comparisonCountLabel = 'Viajes',
    this.comparisonTypicalLabel = 'Típico',
    this.comparisonBestValueLeading,
    this.comparisonTypicalValueLeading,
  });

  final LegacyRouteModel? historicalModel;
  final String comparisonTitle;
  final int comparisonTripCount;
  final num? comparisonBestSeconds;
  final num? comparisonTypicalSeconds;
  final Widget comparisonLeading;
  final String comparisonCountLabel;
  final String comparisonTypicalLabel;
  final Widget? comparisonBestValueLeading;
  final Widget? comparisonTypicalValueLeading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasComparableHistory = historicalModel?.canPlot == true;
    final historicalTypical = hasComparableHistory
        ? historicalModel!.durationForPercentile(50)
        : null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _RouteComparisonColumn(
              title: comparisonTitle,
              titleLeading: comparisonLeading,
              titleColor: colorScheme.onSurface,
              valueColor: colorScheme.onSurface,
              percentileColor: colorScheme.primary,
              tripCount: comparisonTripCount,
              bestSeconds: comparisonBestSeconds,
              bestPercentile: comparisonBestSeconds == null
                  ? null
                  : hasComparableHistory
                  ? historicalModel!.percentileForDuration(
                      comparisonBestSeconds!.toDouble(),
                    )
                  : null,
              typicalSeconds: comparisonTypicalSeconds,
              typicalPercentile: comparisonTypicalSeconds == null
                  ? null
                  : hasComparableHistory
                  ? historicalModel!.percentileForDuration(
                      comparisonTypicalSeconds!.toDouble(),
                    )
                  : null,
              countLabel: comparisonCountLabel,
              bestLabel: 'Mejor',
              typicalLabel: comparisonTypicalLabel,
              bestValueLeading: comparisonBestValueLeading,
              typicalValueLeading: comparisonTypicalValueLeading,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant,
            ),
          ),
          Expanded(
            child: _RouteComparisonColumn(
              title: _historicalUsersTitle(historicalModel),
              titleLeading: _DistributionIcon(color: colorScheme.primary),
              titleColor: colorScheme.primary,
              valueColor: colorScheme.primary,
              tripCount: historicalModel?.totalCount,
              bestSeconds: historicalModel?.bestSeconds,
              typicalSeconds: historicalTypical,
            ),
          ),
        ],
      ),
    );
  }
}

String _historicalUsersTitle(LegacyRouteModel? model) {
  if (model == null) {
    return 'USUARIOS';
  }
  final firstYear = model.firstTripAt.year;
  final lastYear = model.lastTripAt.year;
  if (firstYear == lastYear) {
    return 'USUARIOS $firstYear';
  }
  if (firstYear ~/ 100 == lastYear ~/ 100) {
    return 'USUARIOS $firstYear-${(lastYear % 100).toString().padLeft(2, '0')}';
  }
  return 'USUARIOS $firstYear-$lastYear';
}

class _DistributionIcon extends StatelessWidget {
  const _DistributionIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('historical-distribution-icon'),
      size: const Size(17, 14),
      painter: _DistributionIconPainter(color),
    );
  }
}

class _DistributionIconPainter extends CustomPainter {
  const _DistributionIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(1, size.height - 1)
      ..cubicTo(
        size.width * 0.28,
        size.height - 1,
        size.width * 0.31,
        1,
        size.width * 0.5,
        1,
      )
      ..cubicTo(
        size.width * 0.69,
        1,
        size.width * 0.72,
        size.height - 1,
        size.width - 1,
        size.height - 1,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DistributionIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RouteComparisonColumn extends StatelessWidget {
  const _RouteComparisonColumn({
    required this.title,
    required this.titleLeading,
    required this.titleColor,
    required this.valueColor,
    required this.tripCount,
    required this.bestSeconds,
    required this.typicalSeconds,
    this.countLabel = 'Viajes',
    this.bestLabel = 'Mejor',
    this.typicalLabel = 'Típico',
    this.bestValueLeading,
    this.typicalValueLeading,
    this.bestPercentile,
    this.typicalPercentile,
    this.percentileColor,
  });

  final String title;
  final Widget titleLeading;
  final Color titleColor;
  final Color valueColor;
  final int? tripCount;
  final num? bestSeconds;
  final num? typicalSeconds;
  final String countLabel;
  final String bestLabel;
  final String typicalLabel;
  final Widget? bestValueLeading;
  final Widget? typicalValueLeading;
  final double? bestPercentile;
  final double? typicalPercentile;
  final Color? percentileColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 22, height: 20, child: Center(child: titleLeading)),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  style: textTheme.labelMedium?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RouteComparisonValue(
          label: countLabel,
          value: tripCount?.toString() ?? '—',
          valueColor: valueColor,
        ),
        const SizedBox(height: 12),
        _RouteComparisonMetric(
          label: bestLabel,
          seconds: bestSeconds,
          percentile: bestPercentile,
          valueColor: valueColor,
          percentileColor: percentileColor,
          valueLeading: bestValueLeading,
        ),
        const SizedBox(height: 10),
        _RouteComparisonMetric(
          label: typicalLabel,
          seconds: typicalSeconds,
          percentile: typicalPercentile,
          valueColor: valueColor,
          percentileColor: percentileColor,
          valueLeading: typicalValueLeading,
        ),
      ],
    );
  }
}

class _RouteComparisonMetric extends StatelessWidget {
  const _RouteComparisonMetric({
    required this.label,
    required this.seconds,
    required this.percentile,
    required this.valueColor,
    this.percentileColor,
    this.valueLeading,
  });

  final String label;
  final num? seconds;
  final double? percentile;
  final Color valueColor;
  final Color? percentileColor;
  final Widget? valueLeading;

  @override
  Widget build(BuildContext context) {
    return _RouteComparisonValue(
      label: label,
      value: seconds == null ? '—' : formatPrimeDurationSeconds(seconds!),
      valueColor: valueColor,
      valueLeading: valueLeading,
      secondaryColor: percentileColor,
      secondary: percentile == null
          ? null
          : '(P${percentile!.clamp(0, 100).round()})',
    );
  }
}

class _RouteComparisonValue extends StatelessWidget {
  const _RouteComparisonValue({
    required this.label,
    required this.value,
    required this.valueColor,
    this.secondary,
    this.secondaryColor,
    this.valueLeading,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? secondary;
  final Color? secondaryColor;
  final Widget? valueLeading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 0,
          children: [
            ?valueLeading,
            Text(
              value,
              style: textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (secondary != null)
              Text(
                secondary!,
                style: textTheme.labelMedium?.copyWith(
                  color:
                      secondaryColor ??
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CommunityTripsCard extends StatelessWidget {
  const _CommunityTripsCard({
    required this.rankingAsync,
    required this.historicalModel,
    required this.personalTrips,
    this.onTripSelected,
    required this.onRetry,
  });

  final AsyncValue<CommunityRouteRanking> rankingAsync;
  final LegacyRouteModel? historicalModel;
  final List<Trip> personalTrips;
  final ValueChanged<Trip>? onTripSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('community-route-ranking-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ranking de la comunidad',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            rankingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No se ha podido cargar el ranking de Comunidad.'),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
              data: (ranking) {
                if (ranking.entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nadie de tu Comunidad tiene viajes en este sentido.',
                      key: ValueKey('community-route-empty-list'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (
                      var index = 0;
                      index < ranking.entries.length;
                      index++
                    ) ...[
                      _CommunityTripRow(
                        entry: ranking.entries[index],
                        historicalModel: historicalModel,
                        ownTrip: ranking.entries[index].isCurrentUser
                            ? _matchingOwnTrip(
                                ranking.entries[index],
                                personalTrips,
                              )
                            : null,
                        onTripSelected: onTripSelected,
                      ),
                      if (index < ranking.entries.length - 1)
                        const Divider(height: 1, thickness: 1),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityTripRow extends StatelessWidget {
  const _CommunityTripRow({
    required this.entry,
    required this.historicalModel,
    required this.ownTrip,
    this.onTripSelected,
  });

  final CommunityRouteRankingEntry entry;
  final LegacyRouteModel? historicalModel;
  final Trip? ownTrip;
  final ValueChanged<Trip>? onTripSelected;

  @override
  Widget build(BuildContext context) {
    final background = tripRankBackgroundColor(entry.position);
    final startedAt = entry.isCurrentUser
        ? ownTrip?.startedAt ?? entry.startedAt
        : null;
    final endedAt = startedAt == null
        ? null
        : ownTrip?.endedAt ??
              startedAt.add(Duration(milliseconds: entry.durationMilliseconds));
    final percentile = historicalModel?.canPlot == true
        ? historicalModel!.percentileForDuration(entry.durationSeconds)
        : null;
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (startedAt != null && endedAt != null) ...[
            SizedBox(
              height: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '${formatShortDateTime(startedAt)} - '
                      '${formatShortTime(endedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TripRankingPlacement(rank: entry.position),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _RouteTripUserIdentity(
            avatarAsset: entry.avatarAsset,
            displayName: entry.displayName,
            username: entry.username,
            isCurrentUser: entry.isCurrentUser,
            trailing: startedAt == null
                ? TripRankingPlacement(rank: entry.position)
                : null,
          ),
          if (entry.isCurrentUser && ownTrip?.hasPitStops == true) ...[
            const SizedBox(height: 8),
            for (final pitStop in ownTrip!.pitStops)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: MetricPill(
                  icon: Icons.local_gas_station_outlined,
                  label:
                      '${formatDurationSeconds(pitStop.durationSeconds)}  ·  '
                      '${pitStop.stationName}',
                  backgroundColor: const Color(0xFFDDF3EE),
                  foregroundColor: const Color(0xFF075E56),
                  borderColor: const Color(0xFF91D5C8),
                  dense: true,
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              MetricPill(
                icon: Icons.leaderboard_outlined,
                label: percentile == null
                    ? 'P--'
                    : 'P${percentile.clamp(0, 100).round()}',
                dense: true,
              ),
              MetricPill(
                icon: Icons.timer_outlined,
                label: _formatCommunityDuration(entry.durationMilliseconds),
                dense: true,
              ),
              MetricPill(
                icon: Icons.speed_outlined,
                label: formatSpeedKmh(entry.equivalentAverageSpeedKmh),
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );

    return Material(
      key: ValueKey('community-route-entry-${entry.userId}'),
      color: background,
      child: InkWell(
        onTap: entry.isCurrentUser
            ? (ownTrip == null || onTripSelected == null
                  ? null
                  : () => onTripSelected!(ownTrip!))
            : () => context.push('/social-profile/${entry.userId}'),
        child: content,
      ),
    );
  }
}

Trip? _matchingOwnTrip(
  CommunityRouteRankingEntry entry,
  List<Trip> personalTrips,
) {
  Trip? best;
  for (final trip in personalTrips) {
    if (best == null || trip.durationSeconds < best.durationSeconds) {
      best = trip;
    }
    if (trip.durationSeconds * 1000 == entry.durationMilliseconds) {
      return trip;
    }
  }
  return best;
}

class _PersonalTripsSection extends StatelessWidget {
  const _PersonalTripsSection({
    required this.trips,
    required this.avatarAsset,
    required this.displayName,
    required this.username,
    required this.historicalModel,
    this.onTripSelected,
  });

  final List<Trip> trips;
  final String avatarAsset;
  final String displayName;
  final String? username;
  final LegacyRouteModel? historicalModel;
  final ValueChanged<Trip>? onTripSelected;

  @override
  Widget build(BuildContext context) {
    final orderedTrips = _rankTripsByDuration(trips);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todos mis viajes',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < orderedTrips.length; index++) ...[
          TripCard(
            trip: orderedTrips[index],
            isPersonalRecord: false,
            showRoute: false,
            embedded: true,
            showPrice: false,
            medalRank: index + 1,
            showHistoricalPercentile: true,
            historicalPercentile: historicalModel?.canPlot == true
                ? historicalModel!.percentileForDuration(
                    orderedTrips[index].durationSeconds.toDouble(),
                  )
                : null,
            avatarAsset: avatarAsset,
            identityHeader: _RouteTripUserIdentity(
              key: ValueKey('personal-route-user-${orderedTrips[index].id}'),
              avatarAsset: avatarAsset,
              displayName: displayName,
              username: username,
              isCurrentUser: true,
            ),
            onTap: onTripSelected == null
                ? null
                : () => onTripSelected!(orderedTrips[index]),
          ),
          if (index < orderedTrips.length - 1)
            const Divider(height: 1, thickness: 1),
        ],
      ],
    );
  }
}

class _RouteTripUserIdentity extends StatelessWidget {
  const _RouteTripUserIdentity({
    required this.avatarAsset,
    required this.displayName,
    required this.username,
    required this.isCurrentUser,
    this.trailing,
    super.key,
  });

  final String avatarAsset;
  final String displayName;
  final String? username;
  final bool isCurrentUser;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final normalizedUsername = username?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ProfileAvatar(assetPath: avatarAsset, radius: 23, isSelected: false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (isCurrentUser) ...[
                    const SizedBox(width: 6),
                    const _YouBadge(),
                  ],
                ],
              ),
              if (normalizedUsername?.isNotEmpty == true)
                Text(
                  '@$normalizedUsername',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

List<Trip> _rankTripsByDuration(Iterable<Trip> trips) {
  return [...trips]..sort((a, b) {
    final byDuration = a.durationSeconds.compareTo(b.durationSeconds);
    return byDuration == 0 ? b.startedAt.compareTo(a.startedAt) : byDuration;
  });
}
