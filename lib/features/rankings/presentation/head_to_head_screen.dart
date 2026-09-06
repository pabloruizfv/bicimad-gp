import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/utils/duration_formatters.dart';
import '../../../shared/widgets/head_to_head_icon.dart';
import '../../../shared/widgets/profile_avatar.dart';
import '../../social/domain/social_profile.dart';
import '../domain/head_to_head.dart';

enum _HeadToHeadFilter { all, wins, draws, losses }

class HeadToHeadScreen extends ConsumerStatefulWidget {
  const HeadToHeadScreen({required this.otherUserId, super.key});

  final String otherUserId;

  @override
  ConsumerState<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends ConsumerState<HeadToHeadScreen> {
  _HeadToHeadFilter _filter = _HeadToHeadFilter.all;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentSocialProfileProvider);
    final other = ref.watch(socialProfileDetailsProvider(widget.otherUserId));
    final summary = ref.watch(headToHeadProvider(widget.otherUserId));
    return Scaffold(
      appBar: AppBar(title: const Text('Cara a cara')),
      body: SafeArea(
        child: summary.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton.icon(
              onPressed: () =>
                  ref.invalidate(headToHeadProvider(widget.otherUserId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ),
          data: (data) => other.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Text('No se ha podido cargar este perfil.'),
            ),
            data: (details) {
              if (current == null || details == null) {
                return const Center(child: Text('Perfil no disponible.'));
              }
              return _buildContent(context, current, details.profile, data);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SocialProfile current,
    SocialProfile other,
    HeadToHeadSummary summary,
  ) {
    if (summary.entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'TodavÃ­a no tenÃ©is recorridos en comÃºn',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final filtered = _filteredEntries(summary.entries);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _HeadToHeadHeader(current: current, other: other, summary: summary),
        const SizedBox(height: 14),
        _HeadToHeadFilterBar(
          filter: _filter,
          summary: summary,
          onChanged: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No hay recorridos en este filtro.')),
          )
        else
          for (final entry in filtered)
            _HeadToHeadEntryCard(
              entry: entry,
              current: current,
              other: other,
              onTap: () => context.push(
                '/route-history/${entry.routeKey.originStationId}/'
                '${entry.routeKey.destinationStationId}?view=rankings&mode=community',
              ),
            ),
      ],
    );
  }

  List<HeadToHeadEntry> _filteredEntries(List<HeadToHeadEntry> entries) {
    return entries
        .where((entry) {
          return switch (_filter) {
            _HeadToHeadFilter.all => true,
            _HeadToHeadFilter.wins => entry.result == HeadToHeadResult.win,
            _HeadToHeadFilter.draws => entry.result == HeadToHeadResult.draw,
            _HeadToHeadFilter.losses => entry.result == HeadToHeadResult.loss,
          };
        })
        .toList(growable: false);
  }
}

class _HeadToHeadHeader extends StatelessWidget {
  const _HeadToHeadHeader({
    required this.current,
    required this.other,
    required this.summary,
  });

  final SocialProfile current;
  final SocialProfile other;
  final HeadToHeadSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scoreColor = summary.wins > summary.losses
        ? Colors.green.shade700
        : summary.losses > summary.wins
        ? const Color(0xFF8B1E2D)
        : colors.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _person(current, align: CrossAxisAlignment.start)),
            const SizedBox(width: 8),
            SizedBox(
              width: 112,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HeadToHeadIcon(
                    key: ValueKey('head-to-head-header-icon'),
                    width: 104,
                    height: 52,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ScoreValue(
                            value: summary.wins,
                            emphasized: summary.wins > summary.losses,
                            color: scoreColor,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '\u2014',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: scoreColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                          _ScoreValue(
                            value: summary.losses,
                            emphasized: summary.losses > summary.wins,
                            color: scoreColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _person(other, align: CrossAxisAlignment.end)),
          ],
        ),
      ),
    );
  }

  Widget _person(SocialProfile profile, {required CrossAxisAlignment align}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        ProfileAvatar(assetPath: profile.avatarAsset, radius: 27),
        const SizedBox(height: 5),
        Text(
          profile.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Text(
          '@${profile.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _ScoreValue extends StatelessWidget {
  const _ScoreValue({
    required this.value,
    required this.emphasized,
    required this.color,
  });

  final int value;
  final bool emphasized;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600,
            color: color,
          ),
        ),
        SizedBox(
          width: emphasized ? 28 : 0,
          height: 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: emphasized ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeadToHeadFilterBar extends StatelessWidget {
  const _HeadToHeadFilterBar({
    required this.filter,
    required this.summary,
    required this.onChanged,
  });

  final _HeadToHeadFilter filter;
  final HeadToHeadSummary summary;
  final ValueChanged<_HeadToHeadFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _HeadToHeadFilter.all: 'Todos ${summary.entries.length}',
      _HeadToHeadFilter.wins: 'Ganados ${summary.wins}',
      _HeadToHeadFilter.draws: 'Empates ${summary.draws}',
      _HeadToHeadFilter.losses: 'Perdidos ${summary.losses}',
    };
    return SegmentedButton<_HeadToHeadFilter>(
      segments: [
        for (final value in _HeadToHeadFilter.values)
          ButtonSegment(value: value, label: Text(labels[value]!)),
      ],
      selected: {filter},
      onSelectionChanged: (values) => onChanged(values.first),
      showSelectedIcon: false,
    );
  }
}

class _HeadToHeadEntryCard extends StatelessWidget {
  const _HeadToHeadEntryCard({
    required this.entry,
    required this.current,
    required this.other,
    required this.onTap,
  });

  final HeadToHeadEntry entry;
  final SocialProfile current;
  final SocialProfile other;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resultColor = switch (entry.result) {
      HeadToHeadResult.win => Colors.green.shade700,
      HeadToHeadResult.draw => colors.onSurfaceVariant,
      HeadToHeadResult.loss => colors.error,
    };
    final difference = entry.differenceMilliseconds;
    final differenceText = difference == 0
        ? 'Empate'
        : '${difference > 0 ? '+' : '-'}${_formatDifference(difference.abs())}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RouteStops(
                origin: entry.originStationName,
                destination: entry.destinationStationName,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _timeColumn(
                      context,
                      current,
                      entry.currentDurationMilliseconds,
                    ),
                  ),
                  SizedBox(
                    width: 82,
                    child: Column(
                      children: [
                        Text(
                          differenceText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: resultColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          switch (entry.result) {
                            HeadToHeadResult.win => 'VICTORIA',
                            HeadToHeadResult.draw => 'EMPATE',
                            HeadToHeadResult.loss => 'DERROTA',
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: resultColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _timeColumn(
                      context,
                      other,
                      entry.otherDurationMilliseconds,
                      right: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeColumn(
    BuildContext context,
    SocialProfile profile,
    int milliseconds, {
    bool right = false,
  }) {
    return Column(
      crossAxisAlignment: right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!right) ...[
              ProfileAvatar(assetPath: profile.avatarAsset, radius: 14),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                right ? profile.displayName : '\u0054\u00FA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: right ? TextAlign.right : TextAlign.left,
              ),
            ),
            if (right) ...[
              const SizedBox(width: 6),
              ProfileAvatar(assetPath: profile.avatarAsset, radius: 14),
            ],
          ],
        ),
        Padding(
          padding: EdgeInsets.only(left: right ? 0 : 34, right: right ? 34 : 0),
          child: Text(
            formatDurationSeconds((milliseconds / 1000).round()),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }

  String _formatDifference(int milliseconds) {
    final seconds = milliseconds / 1000;
    if (seconds >= 60) {
      return formatDurationSeconds((seconds).round());
    }
    if (milliseconds % 1000 == 0) {
      return '${seconds.round()} s';
    }
    return '${seconds.toStringAsFixed(3)} s';
  }
}

class _RouteStops extends StatelessWidget {
  const _RouteStops({required this.origin, required this.destination});

  final String origin;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800);
    final arrowColor = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          origin,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, top: 1, bottom: 1),
            child: Icon(Icons.keyboard_arrow_down, color: arrowColor, size: 20),
          ),
        ),
        Text(
          destination,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ],
    );
  }
}
