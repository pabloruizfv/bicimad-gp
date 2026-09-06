import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/social/domain/follow_connection.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/social/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';

void main() {
  testWidgets('consulta el catalogo inicial sin exigir caracteres', (
    tester,
  ) async {
    final social = FakeSocialRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(social)],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comunidad'), findsOneWidget);
    expect(find.text('Todavía no hay otros perfiles.'), findsOneWidget);
    expect(find.text('Escribe al menos dos caracteres.'), findsNothing);
  });

  testWidgets('muestra todos los perfiles iniciales cuando hay menos de 50', (
    tester,
  ) async {
    final social = _SearchSocialRepository([_profile(1), _profile(2)]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(social)],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Persona 1'), findsOneWidget);
    expect(find.text('Persona 2'), findsOneWidget);
    expect(social.queries, ['']);
  });

  testWidgets('con 50 perfiles espera una busqueda y admite una letra', (
    tester,
  ) async {
    final social = _SearchSocialRepository([
      for (var index = 0; index < 50; index++) _profile(index),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(social)],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Busca por @usuario o nombre.'), findsOneWidget);
    expect(find.text('Persona 0'), findsNothing);

    social.results = [_profile(7)];
    await tester.enterText(find.byType(TextField), 'p');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(social.queries, ['', 'p']);
    expect(find.text('Persona 7'), findsOneWidget);
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

  testWidgets('no muestra la estación en resultados de búsqueda compactos', (
    tester,
  ) async {
    final social = _ConnectionsSocialRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(social),
          currentSocialProfileProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField), 'laura');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Metro Lago'), findsNothing);
    expect(find.text('#1:'), findsNothing);
    expect(
      find.byKey(const ValueKey('most-used-station-banner')),
      findsNothing,
    );
  });

  testWidgets('no muestra la estación en seguidores y seguidos compactos', (
    tester,
  ) async {
    final social = _ConnectionsSocialRepository();
    await _pumpConnections(
      tester,
      social: social,
      initialTab: CommunityTab.following,
    );

    expect(find.text('Metro Lago'), findsNothing);
    expect(find.text('#1:'), findsNothing);
  });
}

SocialProfile _profile(int index) => SocialProfile(
  userId: 'user-$index',
  username: 'persona_$index',
  displayName: 'Persona $index',
  avatarKey: '1.png',
  isPublic: true,
);

class _SearchSocialRepository extends FakeSocialRepository {
  _SearchSocialRepository(this.results);

  List<SocialProfile> results;
  final List<String> queries = [];

  @override
  Future<List<SocialProfile>> searchProfiles(String query) async {
    queries.add(query);
    return results;
  }
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
    mostUsedStationName: 'Metro Lago',
    outgoingFollowStatus: FollowStatus.accepted,
    followsCurrentUser: true,
  );

  @override
  Future<List<SocialProfile>> searchProfiles(String query) async => const [
    connectionProfile,
  ];

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
