import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/authentication/data/mock_bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/domain/bicimad_session.dart';
import 'package:bicimad_social/features/profile/data/avatar_repository.dart';
import 'package:bicimad_social/features/profile/presentation/profile_screen.dart';
import 'package:bicimad_social/features/social/application/social_auth_controller.dart';
import 'package:bicimad_social/features/social/application/social_trip_sync_service.dart';
import 'package:bicimad_social/features/social/data/social_profile_cache.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/trips/data/mock_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/community_user.dart';
import 'package:bicimad_social/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets('permite cambiar el nombre visible sin excepciones', (
    tester,
  ) async {
    final authController = _ProfileAuthController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => authController),
          myTripsProvider.overrideWith((ref) async => const []),
          selectedAvatarProvider.overrideWith((ref) async {
            return 'assets/avatar/1.png';
          }),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Ajustes'), findsOneWidget);
    expect(
      find.text('BiciMAD conectado - prototipo experimental'),
      findsNothing,
    );
    expect(find.text('Viajes importados'), findsNothing);
    expect(find.textContaining('sincronización'), findsWidgets);
    expect(find.text('Configuración experimental'), findsNothing);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nuevo Pablo');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Nuevo Pablo'), findsOneWidget);
  });

  testWidgets('muestra las opciones de avatar desde un boton', (tester) async {
    final authController = _ProfileAuthController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => authController),
          myTripsProvider.overrideWith((ref) async => const []),
          selectedAvatarProvider.overrideWith((ref) async {
            return 'assets/avatar/1.png';
          }),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Selecciona tu avatar de piloto'), findsNothing);
    await tester.tap(find.byType(ProfileAvatar).first);
    await tester.pumpAndSettle();

    expect(find.text('Selecciona tu avatar de piloto'), findsOneWidget);
    expect(find.bySemanticsLabel('Avatar 1.png'), findsOneWidget);
  });

  testWidgets('confirma antes de eliminar todos los datos', (tester) async {
    final authController = _ProfileAuthController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => authController),
          myTripsProvider.overrideWith((ref) async => const []),
          selectedAvatarProvider.overrideWith((ref) async {
            return 'assets/avatar/1.png';
          }),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Desconectar BiciMAD'), findsNothing);
    expect(find.textContaining('Historial BiciMAD:'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Eliminar mi cuenta')).dy,
      greaterThan(tester.getTopLeft(find.text('Cerrar sesión')).dy),
    );
    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Eliminar mi cuenta'),
    );
    expect(
      deleteButton.style?.backgroundColor?.resolve({}),
      Theme.of(tester.element(find.byType(ProfileScreen))).colorScheme.error,
    );
    expect(
      deleteButton.style?.foregroundColor?.resolve({}),
      Theme.of(tester.element(find.byType(ProfileScreen))).colorScheme.onError,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar mi cuenta'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('cuenta de bicimad GP'), findsOneWidget);
    expect(find.textContaining('BiciMAD/MPass'), findsOneWidget);
    expect(find.textContaining('Supabase'), findsNothing);
    final warning = tester.widget<Text>(
      find.textContaining('cuenta de bicimad GP'),
    );
    expect(warning.data, contains('dispositivo y de la nube'));
    expect(
      warning.data,
      contains('Esto no elimina tu cuenta ni tu historial original'),
    );
    expect(warning.data, contains('\n\nEsta acción no se puede deshacer.'));

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(authController.deleteMyAccountCalls, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar mi cuenta'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final confirmButton = find.descendant(
      of: dialog,
      matching: find.widgetWithText(FilledButton, 'Eliminar mi cuenta'),
    );
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(authController.deleteMyAccountCalls, 1);
  });

  testWidgets('explica y confirma los cambios de privacidad', (tester) async {
    final authController = _ProfileAuthController();
    final socialController = _ProfileSocialController(
      const SocialProfile(
        userId: 'social-user',
        username: 'pablo',
        displayName: 'Pablo',
        avatarKey: '1.png',
        isPublic: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => authController),
          socialAuthControllerProvider.overrideWith((ref) => socialController),
          myTripsProvider.overrideWith((ref) async => const []),
          selectedAvatarProvider.overrideWith(
            (ref) async => 'assets/avatar/1.png',
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Perfil visible'), findsOneWidget);
    expect(find.text('Cualquiera puede ver tus estadísticas.'), findsOneWidget);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Cambiar a perfil oculto'), findsOneWidget);
    expect(find.textContaining('seguidores aceptados'), findsOneWidget);
    expect(
      find.textContaining('viajes detallados siempre son privados'),
      findsOneWidget,
    );
    expect(socialController.updateCalls, 0);
    await tester.tap(find.text('Hacer oculto'));
    await tester.pumpAndSettle();

    expect(socialController.updateCalls, 1);
    expect(find.text('Perfil oculto'), findsOneWidget);
    expect(
      find.text('Solo tus seguidores pueden ver tus estadísticas.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar a perfil visible'), findsOneWidget);
    expect(find.textContaining('Cualquier usuario podrá ver'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(socialController.updateCalls, 1);
  });
}

class _ProfileAuthController extends AuthController {
  _ProfileAuthController()
    : super(MockBicimadRepository(), MockCommunityRepository()) {
    state = AuthState(
      gateStatus: AuthGateStatus.authenticated,
      session: BicimadSession(
        accessToken: 'fake-token',
        idUser: 'fake-user',
        tokenSecExpiration: 3600,
        obtainedAt: DateTime(2026, 8, 3),
      ),
      user: CommunityUser(
        id: 'current-user',
        externalUserId: 'fake-user',
        displayName: 'Pablo',
        createdAt: DateTime(2026, 8, 3),
      ),
      lastSyncAt: DateTime(2026, 8, 3),
      isLoading: false,
      isSyncing: false,
      syncProgress: null,
      errorMessage: null,
      rememberedEmail: 'user@example.test',
    );
  }

  int deleteMyAccountCalls = 0;

  @override
  Future<void> restoreSession() async {}

  @override
  Future<void> completeDisplayName(String displayName) async {
    final user = state.user;
    if (user == null) {
      return;
    }
    state = state.copyWith(user: user.copyWith(displayName: displayName));
  }

  @override
  Future<bool> deleteMyAccount() async {
    deleteMyAccountCalls += 1;
    return true;
  }
}

class _ProfileSocialController extends SocialAuthController {
  _ProfileSocialController(SocialProfile profile)
    : super(
        repository: FakeSocialRepository(profile: profile),
        cache: SocialProfileCache(store: InMemorySecureKeyValueStore()),
        tripSyncService: SocialTripSyncService(
          socialRepository: FakeSocialRepository(profile: profile),
          localRepository: MockCommunityRepository(),
        ),
        localRepository: MockCommunityRepository(),
        avatarRepository: LocalAvatarRepository(
          store: InMemorySecureKeyValueStore(),
        ),
      ) {
    state = SocialAuthState(status: SocialAuthStatus.ready, profile: profile);
  }

  int updateCalls = 0;

  @override
  Future<void> updateProfile({
    required String displayName,
    required String avatarAsset,
    required bool isPublic,
  }) async {
    updateCalls += 1;
    final profile = state.profile!;
    state = state.copyWith(
      profile: profile.copyWith(
        displayName: displayName,
        avatarKey: avatarAsset.split('/').last,
        isPublic: isPublic,
      ),
    );
  }
}
