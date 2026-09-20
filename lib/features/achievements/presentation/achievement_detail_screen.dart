import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../trips/domain/trip.dart';
import '../../trips/presentation/trips_screen.dart';
import '../domain/achievement.dart';
import 'achievement_badge_assets.dart';
import 'achievement_ranking_section.dart';

class OwnAchievementDetailScreen extends StatefulWidget {
  const OwnAchievementDetailScreen({
    required this.progress,
    this.avatarAsset = 'assets/avatar/1.png',
    super.key,
  });

  final AchievementProgress progress;
  final String avatarAsset;

  @override
  State<OwnAchievementDetailScreen> createState() =>
      _OwnAchievementDetailScreenState();
}

class _OwnAchievementDetailScreenState
    extends State<OwnAchievementDetailScreen> {
  late Map<String, int> _bestByRoute;
  String? _selectedBikeId;

  @override
  void initState() {
    super.initState();
    _bestByRoute = _buildBestByRoute(widget.progress);
    _selectedBikeId = _initialBikeId(widget.progress);
  }

  @override
  void didUpdateWidget(covariant OwnAchievementDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.progress, widget.progress)) {
      _bestByRoute = _buildBestByRoute(widget.progress);
      if (!widget.progress.relatedBikeIds.contains(_selectedBikeId)) {
        _selectedBikeId = _initialBikeId(widget.progress);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final relatedJourneys = _visibleRelatedJourneys(progress, _selectedBikeId);
    return Scaffold(
      appBar: AppBar(title: Text(progress.definition.name)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _OwnAchievementOverviewCard(progress: progress),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: AchievementCommunityRankingSection(
                  definition: progress.definition,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Viajes relacionados',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (progress.definition.rule == AchievementProgressRule.bikeUsage &&
                progress.relatedBikeIds.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _FavoriteBikeSelector(
                    bikeIds: progress.relatedBikeIds,
                    selectedBikeId: _selectedBikeId,
                    onChanged: (bikeId) {
                      setState(() => _selectedBikeId = bikeId);
                    },
                  ),
                ),
              ),
            if (relatedJourneys.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _emptyRelatedMessage(progress.definition.rule),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  key: const ValueKey('achievement-related-journeys-list'),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final journey = relatedJourneys[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index < relatedJourneys.length - 1 ? 10 : 0,
                      ),
                      child: TripCard(
                        key: ValueKey('achievement-journey-${journey.id}'),
                        trip: journey,
                        isPersonalRecord:
                            _bestByRoute[_routeKey(journey)] ==
                            journey.durationSeconds,
                        avatarAsset: widget.avatarAsset,
                        onTap: () => _openJourney(context, journey),
                      ),
                    );
                  }, childCount: relatedJourneys.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteBikeSelector extends StatelessWidget {
  const _FavoriteBikeSelector({
    required this.bikeIds,
    required this.selectedBikeId,
    required this.onChanged,
  });

  final List<String> bikeIds;
  final String? selectedBikeId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      key: const ValueKey('favorite-bike-selector'),
      decoration: InputDecoration(
        labelText: bikeIds.length == 1
            ? 'Bicicleta favorita'
            : 'Bicicletas favoritas',
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('favorite-bike-dropdown'),
          value: selectedBikeId,
          isExpanded: true,
          icon: const Icon(Icons.expand_more),
          items: [
            for (final bikeId in bikeIds)
              DropdownMenuItem(value: bikeId, child: Text(bikeId)),
          ],
          onChanged: bikeIds.length < 2
              ? null
              : (bikeId) {
                  if (bikeId != null) {
                    onChanged(bikeId);
                  }
                },
        ),
      ),
    );
  }
}

class _OwnAchievementOverviewCard extends StatelessWidget {
  const _OwnAchievementOverviewCard({required this.progress});

  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('achievement-overview-card'),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _AchievementHeaderContent(
              assetPath: progress.visibleAssetPath,
              name: progress.definition.name,
              description: progress.definition.description,
            ),
            const SizedBox(height: 16),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 14),
            _DetailValue(
              label: 'Progreso',
              value: progress.definition.formatProgress(progress.progress),
            ),
            const SizedBox(height: 12),
            _AchievementProgressTrack(progress: progress),
          ],
        ),
      ),
    );
  }
}

class PublicAchievementDetailScreen extends StatelessWidget {
  const PublicAchievementDetailScreen({required this.summary, super.key});

  final AchievementSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(summary.definition.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AchievementHeader(
              assetPath: summary.visibleAssetPath,
              name: summary.definition.name,
              description: null,
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _DetailValue(
                  label: 'Requisito',
                  value: summary.definition.formatProgress(
                    (summary.currentLevel ?? summary.definition.levels.first)
                        .threshold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            AchievementCommunityRankingSection(definition: summary.definition),
          ],
        ),
      ),
    );
  }
}

class _AchievementHeader extends StatelessWidget {
  const _AchievementHeader({
    required this.assetPath,
    required this.name,
    required this.description,
  });

  final String assetPath;
  final String name;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: _AchievementHeaderContent(
          assetPath: assetPath,
          name: name,
          description: description,
        ),
      ),
    );
  }
}

class _AchievementHeaderContent extends StatelessWidget {
  const _AchievementHeaderContent({
    required this.assetPath,
    required this.name,
    required this.description,
  });

  final String assetPath;
  final String name;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SvgPicture.asset(assetPath, width: 150, height: 150),
        const SizedBox(height: 8),
        Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (description case final text?) ...[
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _AchievementProgressTrack extends StatelessWidget {
  const _AchievementProgressTrack({required this.progress});

  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final levels = progress.definition.levels;
    const markerSize = 34.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final travelWidth = constraints.maxWidth - markerSize;
        return SizedBox(
          key: const ValueKey('achievement-progress-track'),
          height: 54,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: markerSize / 2,
                right: markerSize / 2,
                top: markerSize / 2 - 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: _milestoneProgress(progress.progress, levels),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              for (var index = 0; index < levels.length; index++)
                Positioned(
                  left: levels.length == 1
                      ? travelWidth / 2
                      : travelWidth * index / (levels.length - 1),
                  top: 0,
                  child: SizedBox(
                    width: markerSize,
                    child: Column(
                      children: [
                        SvgPicture.asset(
                          baseAchievementBadgeAssetPath(levels[index].id),
                          key: ValueKey(
                            'achievement-level-marker-${levels[index].id.name}',
                          ),
                          width: markerSize,
                          height: markerSize,
                        ),
                        Text(
                          '${levels[index].threshold}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.58),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

double _milestoneProgress(
  int progress,
  List<AchievementLevelDefinition> levels,
) {
  if (levels.isEmpty || progress < levels.first.threshold) {
    return 0;
  }
  if (levels.length == 1 || progress >= levels.last.threshold) {
    return 1;
  }
  for (var index = 0; index < levels.length - 1; index++) {
    final current = levels[index];
    final next = levels[index + 1];
    if (progress < next.threshold) {
      final segmentProgress =
          (progress - current.threshold) / (next.threshold - current.threshold);
      return (index + segmentProgress) / (levels.length - 1);
    }
  }
  return 1;
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

String _emptyRelatedMessage(AchievementProgressRule rule) => switch (rule) {
  AchievementProgressRule.pitStops => 'Aún no hay viajes con pit stops.',
  AchievementProgressRule.fastTrips =>
    'Aún no hay viajes por encima de 14 km/h.',
  AchievementProgressRule.longTrips => 'Aún no hay viajes por encima de 5 km.',
  AchievementProgressRule.stationUsage =>
    'Aún no hay usos suficientes de una misma estación.',
  AchievementProgressRule.bikeUsage =>
    'Aún no hay viajes asociados a una bicicleta.',
  AchievementProgressRule.nightTrips =>
    'Aún no hay viajes iniciados de madrugada.',
  AchievementProgressRule.exploredRoutes => 'Aún no hay rutas exploradas.',
};

String _routeKey(Trip trip) =>
    '${trip.originStationId}\u0000${trip.destinationStationId}';

String? _initialBikeId(AchievementProgress progress) =>
    progress.definition.rule == AchievementProgressRule.bikeUsage &&
        progress.relatedBikeIds.isNotEmpty
    ? progress.relatedBikeIds.first
    : null;

List<Trip> _visibleRelatedJourneys(
  AchievementProgress progress,
  String? selectedBikeId,
) {
  if (progress.definition.rule != AchievementProgressRule.bikeUsage ||
      selectedBikeId == null) {
    return progress.relatedJourneys;
  }
  return progress.relatedJourneys
      .where((journey) => journey.bikeIds.contains(selectedBikeId))
      .toList(growable: false);
}

Map<String, int> _buildBestByRoute(AchievementProgress progress) {
  final comparisonTrips = progress.allJourneys.isEmpty
      ? progress.relatedJourneys
      : progress.allJourneys;
  final bestByRoute = <String, int>{};
  for (final journey in comparisonTrips) {
    final routeKey = _routeKey(journey);
    final current = bestByRoute[routeKey];
    if (current == null || journey.durationSeconds < current) {
      bestByRoute[routeKey] = journey.durationSeconds;
    }
  }
  return Map.unmodifiable(bestByRoute);
}

void _openJourney(BuildContext context, Trip journey) {
  context.push(
    '/route-history/'
    '${Uri.encodeComponent(journey.originStationId)}/'
    '${Uri.encodeComponent(journey.destinationStationId)}'
    '?selectedTripId=${Uri.encodeQueryComponent(journey.id)}',
  );
}
