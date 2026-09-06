import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/rankings/domain/head_to_head.dart';
import 'package:bicimad_social/features/rankings/domain/route_key.dart';
import 'package:bicimad_social/features/rankings/presentation/head_to_head_screen.dart';
import 'package:bicimad_social/features/social/domain/profile_statistics.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la cabecera reutiliza el SVG especifico de Cara a cara', (
    tester,
  ) async {
    const current = SocialProfile(
      userId: 'current',
      username: 'pablo',
      displayName: 'Pablo',
      avatarKey: '1.png',
      isPublic: true,
    );
    const other = SocialProfile(
      userId: 'other',
      username: 'marina',
      displayName: 'Marina',
      avatarKey: '2.png',
      isPublic: true,
    );
    const summary = HeadToHeadSummary(
      entries: [
        HeadToHeadEntry(
          routeKey: RouteKey(originStationId: '1', destinationStationId: '2'),
          originStationName: '1 - Origen',
          destinationStationName: '2 - Destino',
          currentDurationMilliseconds: 60000,
          otherDurationMilliseconds: 70000,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSocialProfileProvider.overrideWithValue(current),
          socialProfileDetailsProvider.overrideWith(
            (ref, userId) async => const SocialProfileDetails(profile: other),
          ),
          headToHeadProvider.overrideWith((ref, userId) async => summary),
        ],
        child: const MaterialApp(home: HeadToHeadScreen(otherUserId: 'other')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('head-to-head-header-icon')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('head-to-head-svg')), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('head-to-head-header-icon')))
          .dy,
      tester.getTopLeft(find.byType(ProfileAvatar).first).dy,
    );
    expect(tester.takeException(), isNull);
  });
}
