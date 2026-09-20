import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/avatar_repository.dart';
import '../../trips/domain/community_repository.dart';
import '../data/social_profile_cache.dart';
import '../domain/social_profile.dart';
import '../domain/social_repository.dart';
import 'social_trip_sync_service.dart';

enum SocialAuthStatus {
  waitingForMpass,
  initializing,
  sendingOtp,
  otpPending,
  verifyingOtp,
  needsProfile,
  ready,
  error,
}

class SocialAuthState {
  const SocialAuthState({
    required this.status,
    this.profile,
    this.maskedEmail,
    this.errorMessage,
    this.otpDraft = '',
    this.isOffline = false,
    this.isSyncing = false,
  });

  const SocialAuthState.waiting()
    : status = SocialAuthStatus.waitingForMpass,
      profile = null,
      maskedEmail = null,
      errorMessage = null,
      otpDraft = '',
      isOffline = false,
      isSyncing = false;

  final SocialAuthStatus status;
  final SocialProfile? profile;
  final String? maskedEmail;
  final String? errorMessage;
  final String otpDraft;
  final bool isOffline;
  final bool isSyncing;

  SocialAuthState copyWith({
    SocialAuthStatus? status,
    SocialProfile? profile,
    String? maskedEmail,
    String? errorMessage,
    String? otpDraft,
    bool? isOffline,
    bool? isSyncing,
    bool clearError = false,
  }) {
    return SocialAuthState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      maskedEmail: maskedEmail ?? this.maskedEmail,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      otpDraft: otpDraft ?? this.otpDraft,
      isOffline: isOffline ?? this.isOffline,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

/// Keeps an issued OTP challenge alive across controller/router rebuilds.
///
/// This object is deliberately memory-only and is cleared when MPass changes
/// account or logs out.
class SocialOtpChallengeMemory {
  String? _normalizedEmail;
  String _draft = '';

  bool get hasPendingChallenge => _normalizedEmail != null;
  String get draft => _draft;

  bool matches(String normalizedEmail) => _normalizedEmail == normalizedEmail;

  void markPending(String normalizedEmail) {
    _normalizedEmail = normalizedEmail;
    _draft = '';
  }

  void updateDraft(String value) {
    if (hasPendingChallenge) {
      _draft = value;
    }
  }

  void clear() {
    _normalizedEmail = null;
    _draft = '';
  }
}

class SocialAuthController extends StateNotifier<SocialAuthState> {
  SocialAuthController({
    required SocialRepository repository,
    required SocialProfileCache cache,
    required SocialTripSyncService tripSyncService,
    required CommunityRepository localRepository,
    required AvatarRepository avatarRepository,
    SocialOtpChallengeMemory? otpChallengeMemory,
  }) : // Public parameter names keep dependency injection readable.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _cache = cache,
       // ignore: prefer_initializing_formals
       _tripSyncService = tripSyncService,
       // ignore: prefer_initializing_formals
       _localRepository = localRepository,
       // ignore: prefer_initializing_formals
       _avatarRepository = avatarRepository,
       _otpChallengeMemory = otpChallengeMemory ?? SocialOtpChallengeMemory(),
       super(const SocialAuthState.waiting());

  final SocialRepository _repository;
  final SocialProfileCache _cache;
  final SocialTripSyncService _tripSyncService;
  final CommunityRepository _localRepository;
  final AvatarRepository _avatarRepository;
  final SocialOtpChallengeMemory _otpChallengeMemory;

  String? _email;
  String? _mpassUserId;
  String? _bindingKey;
  Future<void>? _activeBinding;
  Future<void>? _activeOtpSend;

  bool isOtpFlowActiveFor(String email) {
    final normalized = normalizeEmail(email);
    if (normalized == null || !_otpChallengeMemory.matches(normalized)) {
      return false;
    }
    return state.status == SocialAuthStatus.otpPending ||
        state.status == SocialAuthStatus.verifyingOtp;
  }

  Future<void> bindMpass({required String email, required String mpassUserId}) {
    final normalized = normalizeEmail(email);
    if (normalized == null) {
      state = const SocialAuthState(
        status: SocialAuthStatus.error,
        errorMessage: 'No se ha podido preparar la cuenta social.',
      );
      return Future.value();
    }
    if (_otpChallengeMemory.hasPendingChallenge &&
        !_otpChallengeMemory.matches(normalized)) {
      _otpChallengeMemory.clear();
    }
    final key = '$normalized\u0000$mpassUserId';
    if (_otpChallengeMemory.matches(normalized)) {
      _bindingKey = key;
      _email = normalized;
      _mpassUserId = mpassUserId;
      if (state.status != SocialAuthStatus.verifyingOtp) {
        state = SocialAuthState(
          status: SocialAuthStatus.otpPending,
          maskedEmail: _maskEmail(normalized),
          otpDraft: _otpChallengeMemory.draft,
        );
      }
      return Future.value();
    }
    if (_bindingKey == key &&
        state.status != SocialAuthStatus.error &&
        state.status != SocialAuthStatus.waitingForMpass) {
      return _activeBinding ?? Future.value();
    }
    _bindingKey = key;
    _email = normalized;
    _mpassUserId = mpassUserId;
    final operation = _restoreOrStartOtp();
    _activeBinding = operation;
    return operation.whenComplete(() {
      if (identical(_activeBinding, operation)) {
        _activeBinding = null;
      }
    });
  }

  Future<void> _restoreOrStartOtp() async {
    state = SocialAuthState(
      status: SocialAuthStatus.initializing,
      maskedEmail: _maskEmail(_email),
    );
    if (!_repository.isConfigured) {
      state = SocialAuthState(
        status: SocialAuthStatus.error,
        maskedEmail: _maskEmail(_email),
        errorMessage: 'Falta la configuración local de Supabase.',
      );
      return;
    }

    try {
      final hasRestoredSession = await _repository.restoreSession();
      if (hasRestoredSession) {
        final sessionEmail = normalizeEmail(_repository.currentEmail);
        if (sessionEmail != _email) {
          await _repository.signOut();
          await _cache.clear();
          await _sendOtp();
          return;
        }
        await _loadProfileAndSync();
        return;
      }
      await _sendOtp();
    } catch (_) {
      await _recoverCachedProfileOrError();
    }
  }

  Future<void> _sendOtp() {
    final active = _activeOtpSend;
    if (active != null) {
      return active;
    }
    final operation = _performOtpSend();
    _activeOtpSend = operation;
    return operation.whenComplete(() {
      if (identical(_activeOtpSend, operation)) {
        _activeOtpSend = null;
      }
    });
  }

  Future<void> _performOtpSend() async {
    final email = _email;
    if (email == null) {
      return;
    }
    state = state.copyWith(
      status: SocialAuthStatus.sendingOtp,
      clearError: true,
      otpDraft: '',
    );
    try {
      await _repository.sendOtp(email);
      _otpChallengeMemory.markPending(email);
      state = SocialAuthState(
        status: SocialAuthStatus.otpPending,
        maskedEmail: _maskEmail(email),
      );
    } on SocialAuthFailure catch (error) {
      state = SocialAuthState(
        status: SocialAuthStatus.error,
        maskedEmail: _maskEmail(email),
        errorMessage: _otpFailureMessage(error.kind),
      );
    } catch (_) {
      state = SocialAuthState(
        status: SocialAuthStatus.error,
        maskedEmail: _maskEmail(email),
        errorMessage: 'No se ha podido enviar el código. Revisa la conexión.',
      );
    }
  }

  Future<void> verifyOtp(String token) async {
    final email = _email;
    final normalizedToken = token.trim();
    if (email == null ||
        normalizedToken.isEmpty ||
        !_otpChallengeMemory.matches(email)) {
      return;
    }
    _otpChallengeMemory.updateDraft(normalizedToken);
    state = state.copyWith(
      status: SocialAuthStatus.verifyingOtp,
      clearError: true,
      otpDraft: normalizedToken,
    );
    try {
      await _repository.verifyOtp(
        normalizedEmail: email,
        token: normalizedToken,
      );
    } catch (_) {
      state = state.copyWith(
        status: SocialAuthStatus.otpPending,
        errorMessage: 'El código no es válido o ha caducado.',
      );
      return;
    }
    if (normalizeEmail(_repository.currentEmail) != email) {
      await _repository.signOut();
      state = state.copyWith(
        status: SocialAuthStatus.otpPending,
        errorMessage: 'El correo verificado no coincide con MPass.',
      );
      return;
    }
    _otpChallengeMemory.clear();
    try {
      await _loadProfileAndSync();
    } catch (_) {
      await _recoverCachedProfileOrError();
    }
  }

  void updateOtpDraft(String value) {
    final email = _email;
    if (email == null || !_otpChallengeMemory.matches(email)) {
      return;
    }
    _otpChallengeMemory.updateDraft(value);
    state = state.copyWith(otpDraft: value);
  }

  Future<void> _loadProfileAndSync() async {
    final profile = await _repository.getMyProfile();
    if (profile == null) {
      state = SocialAuthState(
        status: SocialAuthStatus.needsProfile,
        maskedEmail: _maskEmail(_email),
      );
      return;
    }
    await _applyProfileLocally(profile);
    await _cache.write(profile);
    state = SocialAuthState(
      status: SocialAuthStatus.ready,
      profile: profile,
      maskedEmail: _maskEmail(_email),
      isSyncing: true,
    );
    try {
      await _synchronizeCloud();
      state = state.copyWith(isSyncing: false, clearError: true);
    } catch (_) {
      state = state.copyWith(
        isSyncing: false,
        isOffline: true,
        errorMessage:
            'El histórico en la nube se actualizará al recuperar conexión.',
      );
    }
  }

  Future<void> createProfile({
    required String username,
    required String displayName,
    required String avatarAsset,
    required bool isPublic,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedName = displayName.trim();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalizedUsername) ||
        normalizedName.isEmpty ||
        normalizedName.length > 40) {
      state = state.copyWith(errorMessage: 'Revisa los datos del perfil.');
      return;
    }
    state = state.copyWith(
      status: SocialAuthStatus.initializing,
      clearError: true,
    );
    try {
      final profile = await _repository.createProfile(
        username: normalizedUsername,
        displayName: normalizedName,
        avatarKey: _avatarKey(avatarAsset),
        isPublic: isPublic,
        mpassUserId: _mpassUserId,
      );
      await _applyProfileLocally(profile);
      await _cache.write(profile);
      state = SocialAuthState(
        status: SocialAuthStatus.ready,
        profile: profile,
        maskedEmail: _maskEmail(_email),
        isSyncing: true,
      );
      try {
        await _synchronizeCloud();
        state = state.copyWith(isSyncing: false);
      } catch (_) {
        state = state.copyWith(
          isSyncing: false,
          isOffline: true,
          errorMessage: 'Perfil creado. La nube se sincronizará más tarde.',
        );
      }
    } catch (_) {
      state = SocialAuthState(
        status: SocialAuthStatus.needsProfile,
        maskedEmail: _maskEmail(_email),
        errorMessage: 'Ese @usuario no está disponible o no se pudo guardar.',
      );
    }
  }

  Future<void> updateProfile({
    required String displayName,
    required String avatarAsset,
    required bool isPublic,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 40) {
      state = state.copyWith(
        errorMessage: 'El nombre debe tener entre 1 y 40 caracteres.',
      );
      return;
    }
    try {
      final profile = await _repository.updateProfile(
        displayName: name,
        avatarKey: _avatarKey(avatarAsset),
        isPublic: isPublic,
      );
      await _applyProfileLocally(profile);
      await _cache.write(profile);
      state = state.copyWith(profile: profile, clearError: true);
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'No se ha podido actualizar el perfil.',
      );
    }
  }

  Future<void> retry() async {
    final active = _activeBinding ?? _activeOtpSend;
    if (active != null) {
      return active;
    }
    _bindingKey = null;
    final email = _email;
    final mpassUserId = _mpassUserId;
    if (email != null && mpassUserId != null) {
      await bindMpass(email: email, mpassUserId: mpassUserId);
    }
  }

  Future<void> synchronizeCloud() async {
    if (state.status != SocialAuthStatus.ready || state.isSyncing) {
      return;
    }
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      await _synchronizeCloud();
      state = state.copyWith(isSyncing: false, isOffline: false);
    } catch (_) {
      state = state.copyWith(
        isSyncing: false,
        isOffline: true,
        errorMessage: 'No se ha podido sincronizar con la nube.',
      );
    }
  }

  Future<void> resetAfterMpassLogout() async {
    _bindingKey = null;
    _email = null;
    _mpassUserId = null;
    _otpChallengeMemory.clear();
    await _cache.clear();
    state = const SocialAuthState.waiting();
  }

  Future<void> _recoverCachedProfileOrError() async {
    final userId = _repository.currentUserId;
    final cached = userId == null ? null : await _cache.read(userId);
    if (cached != null && normalizeEmail(_repository.currentEmail) == _email) {
      await _applyProfileLocally(cached);
      state = SocialAuthState(
        status: SocialAuthStatus.ready,
        profile: cached,
        maskedEmail: _maskEmail(_email),
        isOffline: true,
        errorMessage: 'Modo sin conexión. Se muestran los datos guardados.',
      );
      return;
    }
    state = SocialAuthState(
      status: SocialAuthStatus.error,
      maskedEmail: _maskEmail(_email),
      errorMessage: 'No se ha podido recuperar la sesión social.',
    );
  }

  Future<void> _synchronizeCloud() {
    final email = _email;
    final mpassUserId = _mpassUserId;
    if (email == null || mpassUserId == null) {
      return Future.value();
    }
    return _tripSyncService
        .synchronize(normalizedMpassEmail: email, mpassUserId: mpassUserId)
        .then((_) {});
  }

  Future<void> _applyProfileLocally(SocialProfile profile) async {
    await _localRepository.updateDisplayName(profile.displayName);
    await _avatarRepository.saveSelectedAvatar(profile.avatarAsset);
  }

  String _avatarKey(String asset) {
    final key = asset.split('/').last;
    if (!LocalAvatarRepository.isAvatarAsset(asset)) {
      throw ArgumentError.value(asset, 'avatarAsset');
    }
    return key;
  }

  String _otpFailureMessage(SocialAuthFailureKind kind) {
    return switch (kind) {
      SocialAuthFailureKind.emailNotAuthorized =>
        'El servicio de correo configurado ha rechazado este destinatario. '
            'Revisa la configuracion de Custom SMTP en Supabase.',
      SocialAuthFailureKind.rateLimited =>
        'Se ha alcanzado el limite temporal de codigos. Espera al menos un '
            'minuto antes de reintentar.',
      SocialAuthFailureKind.otpDisabled =>
        'El acceso por codigo OTP esta desactivado en Supabase.',
      SocialAuthFailureKind.signupDisabled =>
        'El alta de nuevos usuarios esta desactivada en Supabase.',
      SocialAuthFailureKind.invalidEmail =>
        'Supabase ha rechazado el formato del correo de MPass.',
      SocialAuthFailureKind.secureConnection =>
        'No se ha podido establecer una conexion segura con Supabase.',
      SocialAuthFailureKind.connection =>
        'No se ha podido conectar con Supabase. Revisa la conexion.',
      SocialAuthFailureKind.serviceUnavailable =>
        'El servicio de autenticacion social no esta disponible temporalmente.',
      SocialAuthFailureKind.unexpectedResponse =>
        'Supabase ha rechazado el envio. Revisa los registros de Auth del proyecto.',
    };
  }

  String _maskEmail(String? email) {
    final parts = email?.split('@');
    if (parts == null || parts.length != 2 || parts.first.isEmpty) {
      return 'tu correo de MPass';
    }
    final local = parts.first;
    final visible = local.length <= 2 ? local[0] : local.substring(0, 2);
    return '$visible***@${parts.last}';
  }
}
