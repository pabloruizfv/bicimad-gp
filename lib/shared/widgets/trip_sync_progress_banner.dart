import 'package:flutter/material.dart';

import '../../features/trips/domain/trip_history_sync.dart';

class TripSyncProgressBanner extends StatelessWidget {
  const TripSyncProgressBanner({required this.progress, super.key});

  final TripHistorySyncProgress progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recuperando viajes...',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
