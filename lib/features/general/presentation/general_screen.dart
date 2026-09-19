import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../app/providers.dart';
import '../../../shared/widgets/carto_tile_layer.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/arcade_user_stats_card.dart';
import '../../../shared/widgets/docking_station_icon.dart';
import '../../../shared/widgets/menu_app_bar.dart';
import '../../achievements/presentation/achievement_detail_screen.dart';
import '../../achievements/presentation/achievement_showcase.dart';
import '../../trips/domain/trip_metrics.dart';
import '../domain/station_usage.dart';
import 'station_map_interaction.dart';

class GeneralScreen extends ConsumerWidget {
  const GeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(generalTripMetricsProvider);
    final stationUsageAsync = ref.watch(stationUsageProvider);
    final avatarAsync = ref.watch(selectedAvatarProvider);
    final showMapTiles = ref.watch(stationUsageMapTilesEnabledProvider);
    final displayName = ref.watch(currentDisplayNameProvider);
    final socialProfile = ref.watch(currentSocialProfileProvider);
    final achievementsAsync = ref.watch(ownAchievementProgressProvider);
    final socialDetails = socialProfile == null
        ? null
        : ref
              .watch(socialProfileDetailsProvider(socialProfile.userId))
              .valueOrNull;

    return Scaffold(
      appBar: const MenuAppBar(title: Text('Mi Perfil')),
      body: SafeArea(
        child: AsyncStateView<GeneralTripMetrics>(
          value: metricsAsync,
          data: (metrics) {
            if (metrics.totalTrips == 0) {
              return const Center(child: Text('No hay viajes disponibles.'));
            }
            final stationUsages = stationUsageAsync.valueOrNull;
            final mostUsedStationName =
                stationUsages == null || stationUsages.isEmpty
                ? null
                : stationUsages.first.station.name;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                ArcadeUserStatsCard(
                  avatarAsset: avatarAsync.valueOrNull ?? 'assets/avatar/1.png',
                  displayName: displayName ?? 'Piloto',
                  username: socialProfile?.username,
                  statistics: ProfileStatsCardData.fromStatistics(metrics),
                  mostUsedStationName: mostUsedStationName,
                  onIdentityTap: () => context.go('/profile'),
                  onTripsTap: () => context.go('/trips'),
                  socialSummary: socialProfile == null
                      ? null
                      : SocialConnectionSummary(
                          followersCount: socialDetails?.followersCount,
                          followingCount: socialDetails?.followingCount,
                          isPublic: socialProfile.isPublic,
                        ),
                  onFollowersTap: socialProfile == null
                      ? null
                      : () => context.go('/community?tab=followers'),
                  onFollowingTap: socialProfile == null
                      ? null
                      : () => context.go('/community?tab=following'),
                  onVisibilityTap: socialProfile == null
                      ? null
                      : () => context.go('/profile'),
                  onMostUsedStationTap:
                      stationUsages == null || stationUsages.isEmpty
                      ? null
                      : () => showStationUsageMap(
                          context,
                          usages: stationUsages,
                          showTiles: showMapTiles,
                          initiallySelected: stationUsages.first,
                        ),
                ),
                const SizedBox(height: 12),
                achievementsAsync.when(
                  data: (progresses) => AchievementShowcase(
                    badges: [
                      for (final progress in progresses)
                        AchievementBadgeViewData.fromProgress(progress),
                    ],
                    onBadgeTap: (index) => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => OwnAchievementDetailScreen(
                          progress: progresses[index],
                          avatarAsset:
                              avatarAsync.valueOrNull ?? 'assets/avatar/1.png',
                        ),
                      ),
                    ),
                  ),
                  loading: () => const AchievementShowcaseLoading(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class StationUsageMap extends StatefulWidget {
  const StationUsageMap({
    required this.usages,
    this.showTiles = true,
    this.onInteractionChanged,
    super.key,
  });

  final List<StationUsage> usages;
  final bool showTiles;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<StationUsageMap> createState() => _StationUsageMapState();
}

class _StationUsageMapState extends State<StationUsageMap> {
  final _mapKey = GlobalKey<_StreetTileMapState>();
  StationUsage? _selected;
  late _MapViewport _viewport;

  @override
  void initState() {
    super.initState();
    _viewport = _initialViewport(widget.usages);
  }

  @override
  void didUpdateWidget(covariant StationUsageMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedCode = _selected?.station.publicCode;
    if (selectedCode != null &&
        !widget.usages.any(
          (usage) => usage.station.publicCode == selectedCode,
        )) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxUses = widget.usages.fold<int>(
      1,
      (max, usage) => usage.uses > max ? usage.uses : max,
    );
    return AspectRatio(
      aspectRatio: 1.22,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _StationMapSurface(
          mapKey: _mapKey,
          usages: widget.usages,
          maxUses: maxUses,
          selected: _selected,
          viewport: _viewport,
          showTiles: widget.showTiles,
          showUsageCounts: true,
          onSelected: (usage) => setState(() => _selected = usage),
          onViewportChanged: (viewport) => _viewport = viewport,
          onInteractionChanged: widget.onInteractionChanged,
          onOpenFullscreen: _openFullscreen,
        ),
      ),
    );
  }

  Future<void> _openFullscreen() async {
    final session = _StationMapSession(
      selected: _selected,
      viewport: _viewport,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _FullScreenStationMap(
          usages: widget.usages,
          showTiles: widget.showTiles,
          session: session,
          title: 'Estaciones más usadas',
          showUsageCounts: true,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _selected = session.selected;
      _viewport = session.viewport;
    });
    _mapKey.currentState?.moveTo(session.viewport);
  }
}

class _StationMapSurface extends StatelessWidget {
  const _StationMapSurface({
    required this.mapKey,
    required this.usages,
    required this.maxUses,
    required this.selected,
    required this.viewport,
    required this.showTiles,
    required this.showUsageCounts,
    required this.onSelected,
    required this.onViewportChanged,
    this.onInteractionChanged,
    this.onOpenFullscreen,
  });

  final GlobalKey<_StreetTileMapState> mapKey;
  final List<StationUsage> usages;
  final int maxUses;
  final StationUsage? selected;
  final _MapViewport viewport;
  final bool showTiles;
  final bool showUsageCounts;
  final ValueChanged<StationUsage?> onSelected;
  final ValueChanged<_MapViewport> onViewportChanged;
  final ValueChanged<bool>? onInteractionChanged;
  final VoidCallback? onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _StreetTileMap(
            key: mapKey,
            usages: usages,
            maxUses: maxUses,
            selected: selected,
            viewport: viewport,
            showTiles: showTiles,
            showUsageCounts: showUsageCounts,
            onSelected: onSelected,
            onViewportChanged: onViewportChanged,
            onInteractionChanged: onInteractionChanged,
          ),
        ),
        if (onOpenFullscreen case final openFullscreen?)
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              child: IconButton(
                key: const ValueKey('station_map_fullscreen_button'),
                tooltip: 'Abrir mapa a pantalla completa',
                onPressed: openFullscreen,
                icon: const Icon(Icons.fullscreen),
              ),
            ),
          ),
        if (selected case final selectedUsage?)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _SelectedStationPanel(
              usage: selectedUsage,
              showUsageCount: showUsageCounts,
            ),
          ),
      ],
    );
  }
}

class _StreetTileMap extends StatefulWidget {
  const _StreetTileMap({
    super.key,
    required this.usages,
    required this.maxUses,
    required this.selected,
    required this.viewport,
    required this.showTiles,
    required this.showUsageCounts,
    required this.onSelected,
    required this.onViewportChanged,
    this.onInteractionChanged,
  });

  final List<StationUsage> usages;
  final int maxUses;
  final StationUsage? selected;
  final _MapViewport viewport;
  final bool showTiles;
  final bool showUsageCounts;
  final ValueChanged<StationUsage?> onSelected;
  final ValueChanged<_MapViewport> onViewportChanged;
  final ValueChanged<bool>? onInteractionChanged;

  @override
  State<_StreetTileMap> createState() => _StreetTileMapState();
}

class _StreetTileMapState extends State<_StreetTileMap> {
  final _controller = MapController();
  final _activePointers = <int>{};
  final _pointerStarts = <int, Offset>{};
  final _movedPointers = <int>{};

  @override
  Widget build(BuildContext context) {
    final orderedUsages = _orderedUsages();
    return FlutterMap(
      key: const ValueKey('station_usage_map_canvas'),
      mapController: _controller,
      options: MapOptions(
        initialCenter: widget.viewport.center,
        initialZoom: widget.viewport.zoom,
        keepAlive: true,
        interactionOptions: const InteractionOptions(
          flags:
              InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom,
        ),
        onPositionChanged: (camera, hasGesture) {
          widget.onViewportChanged(
            _MapViewport(center: camera.center, zoom: camera.zoom),
          );
        },
        onPointerDown: (event, point) => _pointerDown(event),
        onPointerMove: (event, point) => _pointerMove(event),
        onPointerUp: (event, point) => _pointerUp(event),
        onPointerCancel: (event, point) => _pointerFinished(event.pointer),
      ),
      children: [
        if (widget.showTiles)
          CartoTileLayer()
        else
          const _FallbackMapLayer(),
        MarkerLayer(
          markers: [
            for (final usage in orderedUsages)
              Marker(
                point: LatLng(usage.station.latitude, usage.station.longitude),
                width: stationMarkerTouchDiameter,
                height: stationMarkerTouchDiameter,
                child: _StationMarkerBubble(
                  usage: usage,
                  maxUses: widget.maxUses,
                  showUsageCount: widget.showUsageCounts,
                  isSelected:
                      widget.selected?.station.publicCode ==
                      usage.station.publicCode,
                ),
              ),
          ],
        ),
      ],
    );
  }

  void moveTo(_MapViewport viewport) {
    _controller.move(viewport.center, viewport.zoom);
  }

  List<StationUsage> _orderedUsages() {
    final selectedCode = widget.selected?.station.publicCode;
    if (selectedCode == null) {
      return widget.usages;
    }
    return [
      ...widget.usages.where(
        (usage) => usage.station.publicCode != selectedCode,
      ),
      ...widget.usages.where(
        (usage) => usage.station.publicCode == selectedCode,
      ),
    ];
  }

  void _selectNearestStation(Offset tap) {
    final camera = _controller.camera;
    final visibleUsages = <StationUsage>[];
    final positions = <Offset>[];
    for (final usage in widget.usages) {
      final position = camera.latLngToScreenOffset(
        LatLng(usage.station.latitude, usage.station.longitude),
      );
      if (position.dx < 0 ||
          position.dy < 0 ||
          position.dx > camera.size.width ||
          position.dy > camera.size.height) {
        continue;
      }
      visibleUsages.add(usage);
      positions.add(position);
    }
    final index = closestStationIndex(
      tapPosition: tap,
      stationPositions: positions,
    );
    if (index == null) {
      widget.onSelected(null);
      return;
    }
    final nearest = visibleUsages[index];
    final isAlreadySelected =
        widget.selected?.station.publicCode == nearest.station.publicCode;
    widget.onSelected(isAlreadySelected ? null : nearest);
  }

  void _pointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _pointerStarts[event.pointer] = event.localPosition;
    _movedPointers.remove(event.pointer);
    if (_activePointers.length > 1) {
      _movedPointers.addAll(_activePointers);
    }
    if (_activePointers.length == 1) {
      widget.onInteractionChanged?.call(true);
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    final start = _pointerStarts[event.pointer];
    if (start != null && (event.localPosition - start).distance > 8) {
      _movedPointers.add(event.pointer);
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (!_movedPointers.contains(event.pointer)) {
      _selectNearestStation(event.localPosition);
    }
    _pointerFinished(event.pointer);
  }

  void _pointerFinished(int pointer) {
    _activePointers.remove(pointer);
    _pointerStarts.remove(pointer);
    _movedPointers.remove(pointer);
    if (_activePointers.isEmpty) {
      widget.onInteractionChanged?.call(false);
    }
  }

  @override
  void dispose() {
    if (_activePointers.isNotEmpty) {
      widget.onInteractionChanged?.call(false);
    }
    _controller.dispose();
    super.dispose();
  }
}

class _StationMarkerBubble extends StatelessWidget {
  const _StationMarkerBubble({
    required this.usage,
    required this.maxUses,
    required this.showUsageCount,
    required this.isSelected,
  });

  final StationUsage usage;
  final int maxUses;
  final bool showUsageCount;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final baseDiameter = stationMarkerDiameter(
      uses: usage.uses,
      maxUses: maxUses,
    );
    final diameter = isSelected ? baseDiameter * 1.12 : baseDiameter;
    return Semantics(
      label: showUsageCount
          ? '${usage.station.name}: ${usage.uses} usos'
          : usage.station.name,
      child: IgnorePointer(
        child: Center(
          child: AnimatedContainer(
            key: ValueKey('station_marker_${usage.station.publicCode}'),
            duration: const Duration(milliseconds: 160),
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.primary,
              border: Border.all(
                color: Colors.white,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isSelected ? 0.34 : 0.24,
                  ),
                  blurRadius: isSelected ? 11 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FallbackMapLayer extends StatelessWidget {
  const _FallbackMapLayer();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEAF5FF),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: CustomPaint(
          painter: _MapBackgroundPainter(
            colorScheme: Theme.of(context).colorScheme,
          ),
        ),
      ),
    );
  }
}

Future<void> showStationUsageMap(
  BuildContext context, {
  required List<StationUsage> usages,
  required bool showTiles,
  StationUsage? initiallySelected,
  String title = 'Estaciones más usadas',
  bool showUsageCounts = true,
}) {
  if (usages.isEmpty) {
    return Future<void>.value();
  }
  final session = _StationMapSession(
    selected: initiallySelected,
    viewport: _initialViewport(usages),
  );
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => _FullScreenStationMap(
        usages: usages,
        showTiles: showTiles,
        session: session,
        title: title,
        showUsageCounts: showUsageCounts,
      ),
    ),
  );
}

class _FullScreenStationMap extends StatefulWidget {
  const _FullScreenStationMap({
    required this.usages,
    required this.showTiles,
    required this.session,
    required this.title,
    required this.showUsageCounts,
  });

  final List<StationUsage> usages;
  final bool showTiles;
  final _StationMapSession session;
  final String title;
  final bool showUsageCounts;

  @override
  State<_FullScreenStationMap> createState() => _FullScreenStationMapState();
}

class _FullScreenStationMapState extends State<_FullScreenStationMap> {
  final _mapKey = GlobalKey<_StreetTileMapState>();
  late StationUsage? _selected;
  late _MapViewport _viewport;

  @override
  void initState() {
    super.initState();
    _selected = widget.session.selected;
    _viewport = widget.session.viewport;
  }

  @override
  Widget build(BuildContext context) {
    final maxUses = widget.usages.fold<int>(
      1,
      (max, usage) => usage.uses > max ? usage.uses : max,
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: _StationMapSurface(
          mapKey: _mapKey,
          usages: widget.usages,
          maxUses: maxUses,
          selected: _selected,
          viewport: _viewport,
          showTiles: widget.showTiles,
          showUsageCounts: widget.showUsageCounts,
          onSelected: (usage) {
            setState(() => _selected = usage);
            widget.session.selected = usage;
          },
          onViewportChanged: (viewport) {
            _viewport = viewport;
            widget.session.viewport = viewport;
          },
        ),
      ),
    );
  }
}

class _StationMapSession {
  _StationMapSession({required this.selected, required this.viewport});

  StationUsage? selected;
  _MapViewport viewport;
}

class _MapViewport {
  const _MapViewport({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

_MapViewport _initialViewport(List<StationUsage> usages) {
  final points = [
    for (final usage in usages)
      LatLng(usage.station.latitude, usage.station.longitude),
  ];
  return _MapViewport(
    center: _averagePoint(points),
    zoom: _initialZoom(points),
  );
}

class _SelectedStationPanel extends StatelessWidget {
  const _SelectedStationPanel({
    required this.usage,
    required this.showUsageCount,
  });

  final StationUsage usage;
  final bool showUsageCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DockingStationIcon(color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                showUsageCount
                    ? '${usage.station.name} - ${usage.uses} veces'
                    : usage.station.name,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBackgroundPainter extends CustomPainter {
  const _MapBackgroundPainter({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9F1F6),
    );
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.86)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final roadEdgePaint = Paint()
      ..color = const Color(0xFFC8D6DF)
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final roads = <Path>[
      Path()
        ..moveTo(size.width * 0.08, size.height * 0.72)
        ..quadraticBezierTo(
          size.width * 0.32,
          size.height * 0.42,
          size.width * 0.58,
          size.height * 0.55,
        )
        ..quadraticBezierTo(
          size.width * 0.80,
          size.height * 0.67,
          size.width * 0.94,
          size.height * 0.28,
        ),
      Path()
        ..moveTo(size.width * 0.12, size.height * 0.25)
        ..lineTo(size.width * 0.92, size.height * 0.84),
      Path()
        ..moveTo(size.width * 0.18, size.height * 0.92)
        ..lineTo(size.width * 0.80, size.height * 0.10),
      Path()
        ..moveTo(size.width * 0.02, size.height * 0.48)
        ..lineTo(size.width * 0.98, size.height * 0.42),
    ];
    for (final road in roads) {
      canvas.drawPath(road, roadEdgePaint);
      canvas.drawPath(road, roadPaint);
    }

    final minorPaint = Paint()
      ..color = const Color(0xFFBFD0DA)
      ..strokeWidth = 1.4;
    for (var x = -size.height; x < size.width; x += 32) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.45, size.height),
        minorPaint,
      );
    }
    for (var y = 18.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 12), minorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapBackgroundPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme;
  }
}

LatLng _averagePoint(List<LatLng> points) {
  final lat = points.fold<double>(0, (sum, point) => sum + point.latitude);
  final lon = points.fold<double>(0, (sum, point) => sum + point.longitude);
  return LatLng(lat / points.length, lon / points.length);
}

double _initialZoom(List<LatLng> points) {
  if (points.length <= 1) {
    return 14.2;
  }
  final latitudes = points.map((point) => point.latitude).toList();
  final longitudes = points.map((point) => point.longitude).toList();
  final latRange =
      latitudes.reduce((a, b) => a > b ? a : b) -
      latitudes.reduce((a, b) => a < b ? a : b);
  final lonRange =
      longitudes.reduce((a, b) => a > b ? a : b) -
      longitudes.reduce((a, b) => a < b ? a : b);
  final range = latRange > lonRange ? latRange : lonRange;
  if (range < 0.01) {
    return 14;
  }
  if (range < 0.03) {
    return 13;
  }
  return 12;
}
