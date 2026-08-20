import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/social/domain/follow_connection.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/social/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';

void main() {
  testWidgets('muestra el estado vacio de busqueda sin trafico de red', (
    tester,
  ) async {
    final social = FakeSocialRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(social)],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Comunidad'), findsOneWidget);
    expect(find.text('Escribe al menos dos caracteres.'), findsOneWidget);
    expect(social.operations, isEmpty);
  });

  testWidgets('confirma antes de dejar de seguir', (tester) async {
    final social = _ConnectionsSocialRepository();
    await _pumpConnections(
      tester,
      social: social,
      initialTab: CommunityTab.following,
    );

    await tester.tap(find.byTooltip('Dejar de seguir'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dejar de seguir?'), findsOneWidget);
    expect(social.operations, isNot(contains('unfollow')));

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(social.operations, isNot(contains('unfollow')));

    await tester.tap(find.byTooltip('Dejar de seguir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dejar de seguir'));
    await tester.pumpAndSettle();
    expect(social.operations, contains('unfollow'));
  });

  testWidgets('confirma antes de eliminar un seguidor', (tester) async {
    final social = _ConnectionsSocialRepository();
    await _pumpConnections(
      tester,
      social: social,
      initialTab: CommunityTab.followers,
    );

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar seguidor?'), findsOneWidget);
    expect(social.operations, isNot(contains('removeFollower')));

    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(social.operations, contains('removeFollower'));
  });
}

Future<void> _pumpConnections(
  WidgetTester tester, {
  required _ConnectionsSocialRepository social,
  required CommunityTab initialTab,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialRepositoryProvider.overrideWithValue(social),
        currentSocialProfileProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(home: CommunityScreen(initialTab: initialTab)),
    ),
  );
  await tester.pumpAndSettle();
}

class _ConnectionsSocialRepository extends FakeSocialRepository {
  static const connectionProfile = SocialProfile(
    userId: 'other-user',
    username: 'laura',
    displayName: 'Laura',
    avatarKey: '2.png',
    isPublic: true,
    outgoingFollowStatus: FollowStatus.accepted,
    followsCurrentUser: true,
  );

  @override
  Future<List<FollowConnection>> getConnections(ConnectionListType type) async {
    return switch (type) {
      ConnectionListType.followers => [
        FollowConnection(
          profile: connectionProfile,
          status: FollowStatus.accepted,
          direction: FollowDirection.incoming,
          createdAt: DateTime(2026, 8, 1),
        ),
      ],
      ConnectionListType.following => [
        FollowConnection(
          profile: connectionProfile,
          status: FollowStatus.accepted,
          direction: FollowDirection.outgoing,
          createdAt: DateTime(2026, 8, 1),
        ),
      ],
      _ => const [],
    };
  }
}
