import 'package:flutter/material.dart';

import '../../core/models/profile_statistics_values.dart';
import '../../core/utils/duration_formatters.dart';
import '../../core/utils/metric_formatters.dart';
import 'checkered_flag_strip.dart';
import 'profile_avatar.dart';

class ProfileStatsCardData {
  const ProfileStatsCardData({
    required this.totalTrips,
    required this.historySpanDays,
    required this.totalDurationSeconds,
    required this.totalDistanceMeters,
    required this.equivalentAverageSpeedKmh,
    required this.tripsWithDistance,
  });

  factory ProfileStatsCardData.fromStatistics(ProfileStatisticsValues value) {
    return ProfileStatsCardData(
      totalTrips: value.totalTrips,
      historySpanDays: value.historySpanDays,
      totalDurationSeconds: value.totalDurationSeconds,
      totalDistanceMeters: value.totalDistanceMeters,
      equivalentAverageSpeedKmh: value.equivalentAverageSpeedKmh,
      tripsWithDistance: value.tripsWithDistance,
    );
  }

  final int totalTrips;
  final int historySpanDays;
  final int totalDurationSeconds;
  final double totalDistanceMeters;
  final double? equivalentAverageSpeedKmh;
  final int tripsWithDistance;
}

class ArcadeUserStatsCard extends StatelessWidget {
  const ArcadeUserStatsCard({
    required this.avatarAsset,
    required this.displayName,
    required this.username,
    required this.statistics,
    this.socialSummary,
    this.socialAction,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onVisibilityTap,
    this.onTripsTap,
    super.key,
  });

  final String avatarAsset;
  final String displayName;
  final String? username;
  final ProfileStatsCardData? statistics;
  final SocialConnectionSummary? socialSummary;
  final Widget? socialAction;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onVisibilityTap;
  final VoidCallback? onTripsTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('arcade-user-stats-card'),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: colorScheme.primary,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _ArcadeHeaderPainter()),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: CheckeredFlagStrip(height: 8),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            if (username?.trim().isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                '@${username!.trim()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                            ],
                            const SizedBox(height: 8),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ProfileAvatar(
                                assetPath: avatarAsset,
                                radius: 38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: statistics != null
                            ? _StatisticsGrid(
                                totalTrips: statistics!.totalTrips,
                                days: statistics!.historySpanDays,
                                totalDurationSeconds:
                                    statistics!.totalDurationSeconds,
                                totalDistanceMeters:
                                    statistics!.totalDistanceMeters,
                                equivalentAverageSpeedKmh:
                                    statistics!.equivalentAverageSpeedKmh,
                                hasDistance: statistics!.tripsWithDistance > 0,
                                onTripsTap: onTripsTap,
                              )
                            : const _PrivateStatisticsState(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (socialSummary case final summary?)
            _SocialConnectionFooter(
              summary: summary,
              action: socialAction,
              onFollowersTap: onFollowersTap,
              onFollowingTap: onFollowingTap,
              onVisibilityTap: onVisibilityTap,
            ),
        ],
      ),
    );
  }
}

class SocialConnectionSummary {
  const SocialConnectionSummary({
    required this.followersCount,
    required this.followingCount,
    required this.isPublic,
  });

  final int? followersCount;
  final int? followingCount;
  final bool isPublic;
}

class _SocialConnectionFooter extends StatelessWidget {
  const _SocialConnectionFooter({
    required this.summary,
    this.action,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onVisibilityTap,
  });

  final SocialConnectionSummary summary;
  final Widget? action;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onVisibilityTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('social-connection-footer'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('social-followers-action'),
                  onTap: onFollowersTap,
                  borderRadius: BorderRadius.circular(8),
                  child: _SocialCount(
                    value: summary.followersCount,
                    label: 'Seguidores',
                  ),
                ),
              ),
              SizedBox(
                height: 38,
                child: VerticalDivider(color: colorScheme.outlineVariant),
              ),
              Expanded(
                child: InkWell(
                  key: const ValueKey('social-following-action'),
                  onTap: onFollowingTap,
                  borderRadius: BorderRadius.circular(8),
                  child: _SocialCount(
                    value: summary.followingCount,
                    label: 'Siguiendo',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    key: const ValueKey('social-visibility-action'),
                    onTap: onVisibilityTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            summary.isPublic
                                ? Icons.public
                                : Icons.lock_outline,
                            size: 16,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            summary.isPublic ? 'Visible' : 'Oculto',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (action case final actionWidget?) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: actionWidget),
          ],
        ],
      ),
    );
  }
}

class _SocialCount extends StatelessWidget {
  const _SocialCount({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value?.toString() ?? '—',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatisticsGrid extends StatelessWidget {
  const _StatisticsGrid({
    required this.totalTrips,
    required this.days,
    required this.totalDurationSeconds,
    required this.totalDistanceMeters,
    required this.equivalentAverageSpeedKmh,
    required this.hasDistance,
    this.onTripsTap,
  });

  final int totalTrips;
  final int days;
  final int totalDurationSeconds;
  final double? totalDistanceMeters;
  final double? equivalentAverageSpeedKmh;
  final bool hasDistance;
  final VoidCallback? onTripsTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 19,
              child: _HeaderChip(
                key: const ValueKey('stats-trips-action'),
                label: 'Viajes',
                value: '$totalTrips',
                onTap: onTripsTap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 19,
              child: _HeaderChip(label: 'Días', value: '$days'),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 26,
              child: _HeaderChip(
                label: 'En bici',
                value: formatCompactReadableDurationSeconds(
                  totalDurationSeconds,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _HeaderChip(
                label: 'Distancia',
                value: formatDistanceMeters(
                  hasDistance ? totalDistanceMeters : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderChip(
                label: 'Velocidad media',
                value: formatSpeedKmh(
                  hasDistance ? equivalentAverageSpeedKmh : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrivateStatisticsState extends StatelessWidget {
  const _PrivateStatisticsState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Column(
          children: [
            Icon(
              Icons.lock_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Estadísticas privadas',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArcadeHeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.25 + i * 0.18);
      canvas.drawLine(
        Offset(size.width * 0.28, y),
        Offset(size.width * 0.98, y - 30),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcadeHeaderPainter oldDelegate) => false;
}
