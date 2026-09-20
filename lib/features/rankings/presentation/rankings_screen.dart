import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/diagnostics/ranking_performance.dart';
import '../../../core/utils/metric_formatters.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/menu_app_bar.dart';
import '../../../shared/widgets/metric_pill.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../profile/data/avatar_repository.dart';
import '../domain/rankings_sort.dart';
import '../domain/route_key.dart';
import '../domain/route_summary.dart';

class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key});

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  RankingsSortMode _sortMode = RankingsSortMode.position;
  final Stopwatch _totalStopwatch = Stopwatch()..start();
  bool _loggedFirstRender = false;
  bool _loggedTotal = false;

  @override
  Widget build(BuildContext context) {
    final personalSummariesAsync = ref.watch(routePersonalSummariesProvider);
    final historicalPercentilesAsync = ref.watch(
      routeHistoricalPercentilesProvider,
    );
    final percentiles = historicalPercentilesAsync.valueOrNull;
    final elevationCalculator = ref
        .watch(tripElevationCalculatorProvider)
        .valueOrNull;
    final avatarAsset =
        ref.watch(selectedAvatarProvider).valueOrNull ??
        LocalAvatarRepository.defaultAvatarAsset;

    if (personalSummariesAsync.hasValue && !_loggedFirstRender) {
      _loggedFirstRender = true;
      logRankingPerformance('first_render_ready', _totalStopwatch.elapsed);
    }
    if (historicalPercentilesAsync.hasValue && !_loggedTotal) {
      _loggedTotal = true;
      _totalStopwatch.stop();
      logRankingPerformance('total', _totalStopwatch.elapsed);
    }

    return Scaffold(
      appBar: const MenuAppBar(title: Text('Rankings')),
      body: SafeArea(
        child: AsyncStateView<List<RouteSummary>>(
          value: personalSummariesAsync,
          data: (personalSummaries) {
            final summaries = [
              for (final summary in personalSummaries)
                summary.copyWith(
                  historicalPercentile:
                      percentiles?[RouteKey(
                        originStationId: summary.originStationId,
                        destinationStationId: summary.destinationStationId,
                      )],
                ),
            ];
            if (summaries.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => ref
                    .read(authControllerProvider.notifier)
                    .synchronizeTrips(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: const [
                    SizedBox(height: 180),
                    Center(child: Text('Todavía no hay rutas importadas.')),
                  ],
                ),
              );
            }

            final orderedSummaries = sortRouteSummaries(summaries, _sortMode);
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(authControllerProvider.notifier).synchronizeTrips(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: orderedSummaries.length + 1,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      children: [
                        _RankingsSortSelector(
                          value: _sortMode,
                          onChanged: (value) =>
                              setState(() => _sortMode = value),
                        ),
                        if (historicalPercentilesAsync.isLoading) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                      ],
                    );
                  }
                  final cardIndex = index - 1;
                  final summary = orderedSummaries[cardIndex];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push(
                        '/route-history/'
                        '${Uri.encodeComponent(summary.originStationId)}/'
                        '${Uri.encodeComponent(summary.destinationStationId)}'
                        '?view=rankings',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CircuitIcon(variant: cardIndex % 3),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _RouteSummaryText(
                                summary: summary,
                                avatarAsset: avatarAsset,
                                netElevationMeters: elevationCalculator
                                    ?.netMetersBetween(
                                      originLatitude: summary.originLatitude,
                                      originLongitude: summary.originLongitude,
                                      destinationLatitude:
                                          summary.destinationLatitude,
                                      destinationLongitude:
                                          summary.destinationLongitude,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RankingsSortSelector extends StatelessWidget {
  const _RankingsSortSelector({required this.value, required this.onChanged});

  final RankingsSortMode value;
  final ValueChanged<RankingsSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ordenar por',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RankingsSortMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: RankingsSortMode.position,
                icon: Icon(Icons.leaderboard_outlined),
                label: Text('Posición'),
              ),
              ButtonSegment(
                value: RankingsSortMode.speed,
                icon: Icon(Icons.speed_outlined),
                label: Text('Velocidad'),
              ),
              ButtonSegment(
                value: RankingsSortMode.tripCount,
                icon: Icon(Icons.repeat_rounded),
                label: Text('Viajes'),
              ),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ],
    );
  }
}

class _RouteSummaryText extends StatelessWidget {
  const _RouteSummaryText({
    required this.summary,
    required this.avatarAsset,
    required this.netElevationMeters,
  });

  final RouteSummary summary;
  final String avatarAsset;
  final double? netElevationMeters;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.12,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.originStationName,
          style: titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  formatDistanceWithElevation(
                    summary.personalBestDistanceMeters,
                    netElevationMeters,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          summary.destinationStationName,
          style: titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ProfileAvatar(assetPath: avatarAsset, radius: 13),
            const SizedBox(width: 8),
            MetricPill(
              key: const ValueKey('ranking-trip-count-pill'),
              icon: Icons.repeat_rounded,
              label: summary.personalTripCount == 1
                  ? '1 viaje'
                  : '${summary.personalTripCount} viajes',
              dense: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PersonalBestPill(
                percentile: summary.historicalPercentile,
                speedKmh: summary.personalBestSpeedKmh,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PersonalBestPill extends StatelessWidget {
  const _PersonalBestPill({required this.percentile, required this.speedKmh});

  final double? percentile;
  final double? speedKmh;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFF503D00);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w800,
    );
    return DecoratedBox(
      key: const ValueKey('ranking-personal-best-pill'),
      decoration: BoxDecoration(
        color: bicimadArcadeYellow,
        border: Border.all(color: const Color(0xFFE6B800)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.leaderboard_outlined,
                size: 14,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Text(
                percentile == null
                    ? 'P--'
                    : 'P${percentile!.clamp(0, 100).round()}',
                style: labelStyle,
              ),
              const _PillSeparator(),
              const Icon(Icons.speed_outlined, size: 14, color: foreground),
              const SizedBox(width: 4),
              Text(formatSpeedKmh(speedKmh), style: labelStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillSeparator extends StatelessWidget {
  const _PillSeparator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 7),
      child: Text(
        '·',
        style: TextStyle(color: Color(0xFF503D00), fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CircuitIcon extends StatelessWidget {
  const _CircuitIcon({required this.variant});

  final int variant;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 58,
      child: CustomPaint(
        painter: _CircuitIconPainter(
          color: Theme.of(context).colorScheme.primary,
          variant: variant,
        ),
      ),
    );
  }
}

class _CircuitIconPainter extends CustomPainter {
  const _CircuitIconPainter({required this.color, required this.variant});

  final Color color;
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = switch (variant) {
      1 => _secondTrack(size),
      2 => _thirdTrack(size),
      _ => _firstTrack(size),
    };
    canvas.drawPath(path, trackPaint);
  }

  Path _firstTrack(Size size) {
    return Path()
      ..moveTo(size.width * 0.24, size.height * 0.72)
      ..cubicTo(
        size.width * 0.08,
        size.height * 0.54,
        size.width * 0.14,
        size.height * 0.22,
        size.width * 0.42,
        size.height * 0.18,
      )
      ..lineTo(size.width * 0.73, size.height * 0.18)
      ..cubicTo(
        size.width * 0.95,
        size.height * 0.18,
        size.width * 0.96,
        size.height * 0.44,
        size.width * 0.74,
        size.height * 0.46,
      )
      ..lineTo(size.width * 0.46, size.height * 0.46)
      ..cubicTo(
        size.width * 0.29,
        size.height * 0.46,
        size.width * 0.30,
        size.height * 0.62,
        size.width * 0.47,
        size.height * 0.63,
      )
      ..lineTo(size.width * 0.68, size.height * 0.64)
      ..cubicTo(
        size.width * 0.91,
        size.height * 0.65,
        size.width * 0.88,
        size.height * 0.87,
        size.width * 0.63,
        size.height * 0.85,
      )
      ..lineTo(size.width * 0.37, size.height * 0.82)
      ..cubicTo(
        size.width * 0.29,
        size.height * 0.81,
        size.width * 0.25,
        size.height * 0.77,
        size.width * 0.24,
        size.height * 0.72,
      )
      ..close();
  }

  Path _secondTrack(Size size) {
    return Path()
      ..moveTo(size.width * 0.30, size.height * 0.86)
      ..cubicTo(
        size.width * 0.12,
        size.height * 0.82,
        size.width * 0.08,
        size.height * 0.62,
        size.width * 0.18,
        size.height * 0.50,
      )
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.38,
        size.width * 0.20,
        size.height * 0.20,
        size.width * 0.38,
        size.height * 0.14,
      )
      ..lineTo(size.width * 0.68, size.height * 0.14)
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.14,
        size.width * 0.96,
        size.height * 0.34,
        size.width * 0.82,
        size.height * 0.46,
      )
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.57,
        size.width * 0.92,
        size.height * 0.70,
        size.width * 0.76,
        size.height * 0.82,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.91,
        size.width * 0.44,
        size.height * 0.90,
        size.width * 0.30,
        size.height * 0.86,
      )
      ..close();
  }

  Path _thirdTrack(Size size) {
    return Path()
      ..moveTo(size.width * 0.26, size.height * 0.78)
      ..cubicTo(
        size.width * 0.10,
        size.height * 0.66,
        size.width * 0.12,
        size.height * 0.38,
        size.width * 0.30,
        size.height * 0.28,
      )
      ..cubicTo(
        size.width * 0.46,
        size.height * 0.18,
        size.width * 0.62,
        size.height * 0.14,
        size.width * 0.76,
        size.height * 0.22,
      )
      ..cubicTo(
        size.width * 0.94,
        size.height * 0.32,
        size.width * 0.92,
        size.height * 0.58,
        size.width * 0.72,
        size.height * 0.62,
      )
      ..cubicTo(
        size.width * 0.56,
        size.height * 0.66,
        size.width * 0.56,
        size.height * 0.80,
        size.width * 0.72,
        size.height * 0.82,
      )
      ..cubicTo(
        size.width * 0.91,
        size.height * 0.84,
        size.width * 0.88,
        size.height * 0.96,
        size.width * 0.64,
        size.height * 0.94,
      )
      ..cubicTo(
        size.width * 0.48,
        size.height * 0.92,
        size.width * 0.34,
        size.height * 0.86,
        size.width * 0.26,
        size.height * 0.78,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant _CircuitIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.variant != variant;
  }
}
