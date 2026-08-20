import 'dart:async';

import 'package:bicimad_social/features/profile/data/avatar_repository.dart';
import 'package:bicimad_social/features/social/application/social_auth_controller.dart';
import 'package:bicimad_social/features/social/application/social_trip_sync_service.dart';
import 'package:bicimad_social/features/social/data/social_profile_cache.dart';
import 'package:bicimad_social/features/social/domain/social_profile.dart';
import 'package:bicimad_social/features/social/domain/social_repository.dart';
import 'package:bicimad_social/features/trips/data/mock_community_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  test('restaura una sesion social del mismo correo', () async {
    final fixture = await _fixture();

    await fixture.controller.bindMpass(
      email: '  PABLO@example.com ',
      mpassUserId: 'mpass-user',
    );

    expect(fixture.controller.state.status, SocialAuthStatus.ready);
    expect(fixture.social.sentOtpEmails, isEmpty);
    expect(fixture.controller.state.profile?.username, 'pablo_test');
  });

  test('rebind con sesion restaurada no repite restauracion ni OTP', () async {
    final fixture = await _fixture();

    await fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );
    await fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );

    expect(
      fixture.social.operations.where((value) => value == 'restoreSession'),
      hasLength(1),
    );
    expect(fixture.social.sentOtpEmails, isEmpty);
    expect(fixture.controller.state.status, SocialAuthStatus.ready);
  });

  test('espera la restauracion antes de decidir si envia OTP', () async {
    final restoration = Completer<bool>();
    final fixture = await _fixture(
      session: false,
      restoreSessionHandler: () => restoration.future,
    );

    final binding = fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );
    await Future<void>.delayed(Duration.zero);

    expect(fixture.controller.state.status, SocialAuthStatus.initializing);
    expect(fixture.social.sentOtpEmails, isEmpty);

    fixture.social.session = true;
    restoration.complete(true);
    await binding;

    expect(fixture.controller.state.status, SocialAuthStatus.ready);
    expect(fixture.social.sentOtpEmails, isEmpty);
  });

  test('un error al restaurar no se convierte en un envio OTP', () async {
    final fixture = await _fixture(
      session: false,
      restoreSessionHandler: () => Future<bool>.error(StateError('offline')),
    );

    await fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );

    expect(fixture.controller.state.status, SocialAuthStatus.error);
    expect(fixture.social.sentOtpEmails, isEmpty);
  });

  test('sin sesion envia OTP al correo MPass normalizado', () async {
    final fixture = await _fixture(session: false);

    await fixture.controller.bindMpass(
      email: ' PABLO@EXAMPLE.COM ',
      mpassUserId: 'mpass-user',
    );

    expect(fixture.controller.state.status, SocialAuthStatus.otpPending);
    expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
  });

  test('usuario nuevo recibe un OTP y pasa al onboarding', () async {
    final fixture = await _fixture(session: false, profileExists: false);

    await fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );
    await fixture.controller.verifyOtp('123456');

    expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
    expect(fixture.social.verifiedOtpTokens, ['123456']);
    expect(fixture.controller.state.status, SocialAuthStatus.needsProfile);
  });

  test(
    'usuario existente en otro movil recibe un OTP y recupera su perfil',
    () async {
      final fixture = await _fixture(session: false);

      await fixture.controller.bindMpass(
        email: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );
      await fixture.controller.verifyOtp('123456');

      expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
      expect(fixture.social.verifiedOtpTokens, ['123456']);
      expect(fixture.controller.state.status, SocialAuthStatus.ready);
      expect(fixture.controller.state.profile?.username, 'pablo_test');
    },
  );

  test('dos enlaces MPass concurrentes comparten un unico envio OTP', () async {
    final releaseSend = Completer<void>();
    final fixture = await _fixture(
      session: false,
      sendOtpHandler: (_) => releaseSend.future,
    );

    final first = fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );
    final second = fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );

    await Future<void>.delayed(Duration.zero);
    expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
    releaseSend.complete();
    await Future.wait([first, second]);
    expect(fixture.social.sentOtpEmails, hasLength(1));
  });

  test(
    'volver a enlazar mientras espera el codigo no reenvia el OTP',
    () async {
      final fixture = await _fixture(session: false);

      await fixture.controller.bindMpass(
        email: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );
      expect(
        fixture.controller.isOtpFlowActiveFor(' PABLO@EXAMPLE.COM '),
        isTrue,
      );
      await fixture.controller.bindMpass(
        email: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );

      expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
      expect(fixture.controller.state.status, SocialAuthStatus.otpPending);
      expect(fixture.social.operations, ['restoreSession', 'sendOtp']);

      await fixture.controller.verifyOtp('123456');

      expect(fixture.social.verifiedOtpTokens, ['123456']);
      expect(fixture.controller.state.status, SocialAuthStatus.ready);
    },
  );

  test('challenge pendiente sobrevive a reconstruir el controlador', () async {
    final memory = SocialOtpChallengeMemory();
    final fixture = await _fixture(session: false, otpChallengeMemory: memory);
    await fixture.controller.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );
    fixture.controller.updateOtpDraft('123');

    final replacement = SocialAuthController(
      repository: fixture.social,
      cache: SocialProfileCache(store: InMemorySecureKeyValueStore()),
      tripSyncService: SocialTripSyncService(
        socialRepository: fixture.social,
        localRepository: MockCommunityRepository(),
      ),
      localRepository: MockCommunityRepository(),
      avatarRepository: LocalAvatarRepository(
        store: InMemorySecureKeyValueStore(),
      ),
      otpChallengeMemory: memory,
    );

    await replacement.bindMpass(
      email: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );

    expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
    expect(replacement.state.status, SocialAuthStatus.otpPending);
    expect(replacement.state.otpDraft, '123');
  });

  test('cambiar el correo MPass cancela el challenge anterior', () async {
    final fixture = await _fixture(session: false);
    await fixture.controller.bindMpass(
      email: 'first@example.com',
      mpassUserId: 'mpass-user',
    );

    await fixture.controller.bindMpass(
      email: 'second@example.com',
      mpassUserId: 'mpass-user',
    );

    expect(fixture.social.sentOtpEmails, [
      'first@example.com',
      'second@example.com',
    ]);
    expect(fixture.controller.state.status, SocialAuthStatus.otpPending);
    expect(fixture.controller.state.maskedEmail, startsWith('se'));
  });

  test(
    'correo social distinto cierra la sesion anterior y solicita OTP',
    () async {
      final fixture = await _fixture(email: 'other@example.com');

      await fixture.controller.bindMpass(
        email: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );

      expect(fixture.social.signOutCalls, 1);
      expect(fixture.social.sentOtpEmails, ['pablo@example.com']);
      expect(fixture.controller.state.status, SocialAuthStatus.otpPending);
    },
  );

  test(
    'crea perfil con username normalizado y luego solo edita campos mutables',
    () async {
      final fixture = await _fixture(profileExists: false);
      await fixture.controller.bindMpass(
        email: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );
      expect(fixture.controller.state.status, SocialAuthStatus.needsProfile);

      await fixture.controller.createProfile(
        username: 'Pablo_23',
        displayName: 'Pablo Social',
        avatarAsset: 'assets/avatar/2.png',
        isPublic: false,
      );
      await fixture.controller.updateProfile(
        displayName: 'Pablo Nuevo',
        avatarAsset: 'assets/avatar/3.png',
        isPublic: true,
      );

      expect(fixture.controller.state.profile?.username, 'pablo_23');
      expect(fixture.controller.state.profile?.displayName, 'Pablo Nuevo');
      expect(fixture.controller.state.profile?.avatarKey, '3.png');
      expect(fixture.controller.state.profile?.isPublic, isTrue);
    },
  );

  test(
    'explica un rechazo del Custom SMTP sin sugerir una invitacion',
    () async {
      final fixture = await _fixture(
        session: false,
        sendOtpError: const SocialAuthFailure(
          SocialAuthFailureKind.emailNotAuthorized,
        ),
      );

      await fixture.controller.bindMpass(
        email: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );

      expect(fixture.controller.state.status, SocialAuthStatus.error);
      expect(fixture.controller.state.errorMessage, contains('Custom SMTP'));
      expect(fixture.controller.state.errorMessage, isNot(contains('equipo')));
      expect(fixture.controller.state.errorMessage, isNot(contains('pablo')));
    },
  );
}

Future<_Fixture> _fixture({
  bool session = true,
  bool profileExists = true,
  String email = 'pablo@example.com',
  Object? sendOtpError,
  Future<void> Function(String email)? sendOtpHandler,
  Future<bool> Function()? restoreSessionHandler,
  SocialOtpChallengeMemory? otpChallengeMemory,
}) async {
  final store = InMemorySecureKeyValueStore();
  final local = MockCommunityRepository();
  await local.createOrRecoverUser(externalUserId: 'mpass-user');
  final social = FakeSocialRepository(
    session: session,
    email: email,
    profile: profileExists
        ? const SocialProfile(
            userId: 'social-user-1',
            username: 'pablo_test',
            displayName: 'Pablo',
            avatarKey: '1.png',
            isPublic: true,
          )
        : null,
    sendOtpError: sendOtpError,
    sendOtpHandler: sendOtpHandler,
    restoreSessionHandler: restoreSessionHandler,
  );
  return _Fixture(
    social: social,
    controller: SocialAuthController(
      repository: social,
      cache: SocialProfileCache(store: store),
      tripSyncService: SocialTripSyncService(
        socialRepository: social,
        localRepository: local,
      ),
      localRepository: local,
      avatarRepository: LocalAvatarRepository(store: store),
      otpChallengeMemory: otpChallengeMemory,
    ),
  );
}

class _Fixture {
  const _Fixture({required this.social, required this.controller});

  final FakeSocialRepository social;
  final SocialAuthController controller;
}
