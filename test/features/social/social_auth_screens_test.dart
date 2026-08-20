import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/profile/data/avatar_repository.dart';
import 'package:bicimad_social/features/social/application/social_auth_controller.dart';
import 'package:bicimad_social/features/social/application/social_trip_sync_service.dart';
import 'package:bicimad_social/features/social/data/social_profile_cache.dart';
import 'package:bicimad_social/features/social/presentation/social_onboarding_screen.dart';
import 'package:bicimad_social/features/social/presentation/social_otp_screen.dart';
import 'package:bicimad_social/features/trips/data/mock_community_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets('OTP pide solo el codigo social', (tester) async {
    final controller = _PresentedSocialController(
      const SocialAuthState(
        status: SocialAuthStatus.otpPending,
        maskedEmail: 'pa***@example.com',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialAuthControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: SocialOtpScreen()),
      ),
    );

    expect(find.text('Verifica tu correo'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.textContaining('pa***@example.com'), findsOneWidget);
    expect(find.textContaining('bandeja de spam'), findsOneWidget);
    expect(find.byIcon(Icons.password_outlined), findsNothing);
    expect(find.text('Reenviar código'), findsNothing);
  });

  testWidgets('OTP conserva el codigo durante rebuild de la pantalla', (
    tester,
  ) async {
    final social = FakeSocialRepository(session: false);
    final local = MockCommunityRepository();
    final controller = SocialAuthController(
      repository: social,
      cache: SocialProfileCache(store: InMemorySecureKeyValueStore()),
      tripSyncService: SocialTripSyncService(
        socialRepository: social,
        localRepository: local,
      ),
      localRepository: local,
      avatarRepository: LocalAvatarRepository(
        store: InMemorySecureKeyValueStore(),
      ),
    );
    await controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );

    Widget buildScreen(Key key) => ProviderScope(
      overrides: [
        socialAuthControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(home: SocialOtpScreen(key: key)),
    );

    await tester.pumpWidget(buildScreen(const ValueKey('first')));
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.pumpWidget(buildScreen(const ValueKey('rebuilt')));
    await tester.pump();

    expect(find.text('123456'), findsOneWidget);
    expect(social.sentOtpEmails, ['pablo@example.com']);
  });

  testWidgets('onboarding presenta usuario nombre avatar y privacidad', (
    tester,
  ) async {
    final controller = _PresentedSocialController(
      const SocialAuthState(status: SocialAuthStatus.needsProfile),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialAuthControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: SocialOnboardingScreen()),
      ),
    );

    expect(find.text('@usuario'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(4));
  });
}

class _PresentedSocialController extends SocialAuthController {
  _PresentedSocialController(SocialAuthState presentedState)
    : super(
        repository: FakeSocialRepository(),
        cache: SocialProfileCache(store: InMemorySecureKeyValueStore()),
        tripSyncService: SocialTripSyncService(
          socialRepository: FakeSocialRepository(),
          localRepository: MockCommunityRepository(),
        ),
        localRepository: MockCommunityRepository(),
        avatarRepository: LocalAvatarRepository(
          store: InMemorySecureKeyValueStore(),
        ),
      ) {
    state = presentedState;
  }
}
