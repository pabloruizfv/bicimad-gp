import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/app/router.dart';
import 'package:bicimad_social/features/social/application/social_auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restauracion social permanece en la pantalla neutra', () {
    expect(
      resolveAppRedirect(
        location: '/',
        authGateStatus: AuthGateStatus.authenticated,
        needsDisplayName: false,
        socialStatus: SocialAuthStatus.initializing,
      ),
      isNull,
    );
  });

  test('otp pendiente conserva su ruta durante reinicializacion MPass', () {
    expect(
      resolveAppRedirect(
        location: '/social-otp',
        authGateStatus: AuthGateStatus.initializing,
        needsDisplayName: false,
        socialStatus: SocialAuthStatus.otpPending,
      ),
      isNull,
    );
  });

  test('otp pendiente recupera su ruta tras reconstruir el router', () {
    expect(
      resolveAppRedirect(
        location: '/',
        authGateStatus: AuthGateStatus.authenticated,
        needsDisplayName: false,
        socialStatus: SocialAuthStatus.otpPending,
      ),
      '/social-otp',
    );
    expect(
      resolveAppRedirect(
        location: '/general',
        authGateStatus: AuthGateStatus.sessionRecoveryError,
        needsDisplayName: false,
        socialStatus: SocialAuthStatus.verifyingOtp,
      ),
      '/social-otp',
    );
  });

  test('un cierre MPass real prevalece sobre un challenge antiguo', () {
    expect(
      resolveAppRedirect(
        location: '/social-otp',
        authGateStatus: AuthGateStatus.unauthenticated,
        needsDisplayName: false,
        socialStatus: SocialAuthStatus.otpPending,
      ),
      '/login',
    );
  });
}
