import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../app/providers.dart';
import '../../../core/utils/decimal_amount.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/utils/metric_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/checkered_flag_strip.dart';
import '../../../shared/widgets/docking_station_icon.dart';
import '../../../shared/widgets/info_row.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../profile/data/avatar_repository.dart';
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
    super.key,
  });

  final RouteKey routeKey;
  final String? selectedTripId;
  final bool showOverview;
  final bool allowTripNavigation;

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
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (showOverview) ...[
                  _RouteOverviewCard(
                    trip: selectedTrip,
                    stages: _stagesForJourney(
                      selectedTrip,
                      stagesAsync.valueOrNull ?? const [],
                    ),
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
                    modelAsync: legacyModelAsync,
                    personalTrips: trips,
                    personalStatistics: statistics,
                    avatarAsset: avatarAsset,
                    onTripSelected: allowTripNavigation
                        ? (trip) => context.push(
                            '/route-history/'
                            '${Uri.encodeComponent(trip.navigationOriginStationId)}/'
                            '${Uri.encodeComponent(trip.navigationDestinationStationId)}'
                            '?selectedTripId=${Uri.encodeQueryComponent(trip.navigationJourneyId)}',
                          )
                        : null,
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
    required this.personalContext,
  });

  final Trip trip;
  final List<Trip> stages;
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
                      from: stops[index],
                      to: stops[index + 1],
                      metrics: segments[index],
                      color: colorScheme.primary,
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
                  label: 'Bicicleta',
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

String _formatBikeUsage(Trip trip) {
  if (!trip.hasCompleteBikeData || trip.bikeIds.isEmpty) {
    return 'No disponible';
  }
  if (trip.bikeIds.length == 1) {
    return trip.bikeIds.single;
  }
  return 'Varias: ${trip.bikeIds.join(' · ')}';
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
  return [
    _RouteStop(
      name: trip.originStationName,
      kind: _RouteStopKind.origin,
      color: colorScheme.primary,
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
      kind: _RouteStopKind.destination,
      color: Colors.black,
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
  });

  final _RouteStop from;
  final _RouteStop to;
  final _RouteSegmentMetrics metrics;
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
        ],
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
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
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

class _LegacyHistorySection extends StatelessWidget {
  const _LegacyHistorySection({
    required this.modelAsync,
    required this.personalTrips,
    required this.personalStatistics,
    required this.avatarAsset,
    this.onTripSelected,
  });

  final AsyncValue<LegacyRouteModel?> modelAsync;
  final List<Trip> personalTrips;
  final RouteStatistics personalStatistics;
  final String avatarAsset;
  final ValueChanged<Trip>? onTripSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mis viajes vs Histórico usuarios BiciMAD',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                modelAsync.when(
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => const Text(
                    'No se ha podido leer el historico comparable.',
                  ),
                  data: (model) {
                    if (model == null || !model.canPlot) {
                      return const Text(
                        'No hay suficiente historico comparable para esta ruta.',
                      );
                    }

                    final rankedTrips = _rankTripsByDuration(personalTrips);
                    final rangeStart = model.bestSeconds;
                    final rangeEnd = model.upperCutoffSeconds;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: _LegacyDurationChart(
                            painter: _LegacyCurvePainter(
                              points: model.smoothedDensityPoints(),
                              personalDurations: [
                                for (final trip in rankedTrips)
                                  trip.durationSeconds.toDouble(),
                              ],
                              rangeStart: rangeStart,
                              rangeEnd: rangeEnd,
                              colorScheme: Theme.of(context).colorScheme,
                            ),
                            trips: rankedTrips,
                            avatarAsset: avatarAsset,
                            rangeStart: rangeStart,
                            rangeEnd: rangeEnd,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _RouteHistoryComparison(
                          historicalModel: model,
                          personalStatistics: personalStatistics,
                          avatarAsset: avatarAsset,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _PersonalTripsSection(
              trips: personalTrips,
              avatarAsset: avatarAsset,
              historicalModel: modelAsync.valueOrNull,
              onTripSelected: onTripSelected,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegacyDurationChart extends StatelessWidget {
  const _LegacyDurationChart({
    required this.painter,
    required this.trips,
    required this.avatarAsset,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final _LegacyCurvePainter painter;
  final List<Trip> trips;
  final String avatarAsset;
  final double rangeStart;
  final double rangeEnd;

  @override
  Widget build(BuildContext context) {
    final avatarTrips = trips.reversed.toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartRight = constraints.maxWidth - _legacyChartRight;
        final chartWidth = chartRight - _legacyChartLeft;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: painter)),
            if (chartWidth > 0 && rangeEnd > rangeStart)
              for (final trip in avatarTrips)
                if (trip.durationSeconds >= rangeStart)
                  Positioned(
                    key: ValueKey('legacy-chart-avatar-${trip.id}'),
                    left:
                        (_markerX(
                                  trip.durationSeconds.toDouble(),
                                  chartWidth,
                                  chartRight,
                                ) -
                                11)
                            .clamp(0, constraints.maxWidth - 22),
                    top: 2,
                    child: IgnorePointer(
                      child: ProfileAvatar(
                        assetPath: avatarAsset,
                        radius: 11,
                        isSelected: false,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }

  double _markerX(double duration, double chartWidth, double chartRight) {
    if (duration > rangeEnd) return chartRight;
    return _legacyChartLeft +
        ((duration - rangeStart) / (rangeEnd - rangeStart)) * chartWidth;
  }
}

const _legacyChartLeft = 42.0;
const _legacyChartTop = 26.0;
const _legacyChartRight = 8.0;
const _legacyChartBottom = 28.0;

class _LegacyCurvePainter extends CustomPainter {
  const _LegacyCurvePainter({
    required this.points,
    required this.personalDurations,
    required this.rangeStart,
    required this.rangeEnd,
    required this.colorScheme,
  });

  final List<HistogramPoint> points;
  final List<double> personalDurations;
  final double rangeStart;
  final double rangeEnd;
  final ColorScheme colorScheme;

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
    if (maxDensity <= 0) {
      return;
    }

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

    for (var index = personalDurations.length - 1; index >= 0; index--) {
      final duration = personalDurations[index];
      if (duration < rangeStart) continue;
      final x = duration > rangeEnd ? chart.right : _mapX(duration, chart);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.top),
        Paint()
          ..color = tripRankAccentColor(index + 1)
          ..strokeWidth = index < 3 ? 2.5 : 1.2,
      );
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    _paintAxisLabel(
      canvas,
      textPainter,
      formatReadableDurationSeconds(rangeStart),
      Offset(chart.left, chart.bottom + 6),
    );
    _paintAxisLabel(
      canvas,
      textPainter,
      formatReadableDurationSeconds(rangeEnd),
      Offset(chart.right - 58, chart.bottom + 6),
    );
  }

  @override
  bool shouldRepaint(covariant _LegacyCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.personalDurations != personalDurations ||
        oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd;
  }

  double _mapX(double seconds, Rect chart) {
    return chart.left +
        ((seconds - rangeStart) / (rangeEnd - rangeStart)) * chart.width;
  }

  void _paintAxisLabel(
    Canvas canvas,
    TextPainter textPainter,
    String text,
    Offset offset,
  ) {
    textPainter
      ..text = TextSpan(
        text: text,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
      )
      ..layout(maxWidth: 70);
    textPainter.paint(canvas, offset);
  }
}

class _RouteHistoryComparison extends StatelessWidget {
  const _RouteHistoryComparison({
    required this.historicalModel,
    required this.personalStatistics,
    required this.avatarAsset,
  });

  final LegacyRouteModel historicalModel;
  final RouteStatistics personalStatistics;
  final String avatarAsset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final historicalTypical = historicalModel.durationForPercentile(50);
    final personalBest = personalStatistics.bestDurationSeconds;
    final personalTypical = personalStatistics.medianDurationSeconds;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _RouteComparisonColumn(
              title: 'MIS VIAJES',
              titleLeading: ProfileAvatar(
                key: const ValueKey('personal-comparison-avatar'),
                assetPath: avatarAsset,
                radius: 10,
                isSelected: false,
              ),
              titleColor: colorScheme.onSurface,
              valueColor: colorScheme.onSurface,
              percentileColor: colorScheme.primary,
              tripCount: personalStatistics.totalTrips,
              bestSeconds: personalBest,
              bestPercentile: personalBest == null
                  ? null
                  : historicalModel.percentileForDuration(
                      personalBest.toDouble(),
                    ),
              typicalSeconds: personalTypical,
              typicalPercentile: personalTypical == null
                  ? null
                  : historicalModel.percentileForDuration(personalTypical),
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
              tripCount: historicalModel.totalCount,
              bestSeconds: historicalModel.bestSeconds,
              typicalSeconds: historicalTypical,
            ),
          ),
        ],
      ),
    );
  }
}

String _historicalUsersTitle(LegacyRouteModel model) {
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
    this.bestPercentile,
    this.typicalPercentile,
    this.percentileColor,
  });

  final String title;
  final Widget titleLeading;
  final Color titleColor;
  final Color valueColor;
  final int tripCount;
  final num? bestSeconds;
  final num? typicalSeconds;
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
          label: 'Viajes',
          value: '$tripCount',
          valueColor: valueColor,
        ),
        const SizedBox(height: 12),
        _RouteComparisonMetric(
          label: 'Mejor',
          seconds: bestSeconds,
          percentile: bestPercentile,
          valueColor: valueColor,
          percentileColor: percentileColor,
        ),
        const SizedBox(height: 10),
        _RouteComparisonMetric(
          label: 'Típico',
          seconds: typicalSeconds,
          percentile: typicalPercentile,
          valueColor: valueColor,
          percentileColor: percentileColor,
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
  });

  final String label;
  final num? seconds;
  final double? percentile;
  final Color valueColor;
  final Color? percentileColor;

  @override
  Widget build(BuildContext context) {
    return _RouteComparisonValue(
      label: label,
      value: seconds == null ? '—' : formatPrimeDurationSeconds(seconds!),
      valueColor: valueColor,
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
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? secondary;
  final Color? secondaryColor;

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

class _PersonalTripsSection extends StatelessWidget {
  const _PersonalTripsSection({
    required this.trips,
    required this.avatarAsset,
    required this.historicalModel,
    this.onTripSelected,
  });

  final List<Trip> trips;
  final String avatarAsset;
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
            medalRank: index < 3 ? index + 1 : null,
            showHistoricalPercentile: true,
            historicalPercentile: historicalModel?.canPlot == true
                ? historicalModel!.percentileForDuration(
                    orderedTrips[index].durationSeconds.toDouble(),
                  )
                : null,
            avatarAsset: avatarAsset,
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

List<Trip> _rankTripsByDuration(Iterable<Trip> trips) {
  return [...trips]..sort((a, b) {
    final byDuration = a.durationSeconds.compareTo(b.durationSeconds);
    return byDuration == 0 ? b.startedAt.compareTo(a.startedAt) : byDuration;
  });
}
