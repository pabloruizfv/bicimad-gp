import '../../../core/errors/app_exception.dart';
import '../../../core/diagnostics/bicimad_diagnostics.dart';
import '../../trips/data/bicimad_trip_mapper.dart';
import '../../trips/domain/trip.dart';
import '../domain/bicimad_repository.dart';
import '../domain/mpass_session.dart';
import 'bicimad_secure_storage.dart';
import 'mpass_api_client.dart';
import 'technical_config_resolver.dart';

class RealBicimadRepository implements BicimadRepository {
  RealBicimadRepository({
    required this.apiClient,
    required this.secureStorage,
    required this.technicalConfigResolver,
    this.mapper = const BicimadTripMapper(),
  });

  final MpassApiClient apiClient;
  final BicimadSecureStorage secureStorage;
  final TechnicalConfigResolver technicalConfigResolver;
  final BicimadTripMapper mapper;
  String? _activeSyncUserId;
  String? _activeSyncNif;

  @override
  Future<MpassSession> login({
    required String email,
    required String password,
  }) async {
    final resolvedConfig = await technicalConfigResolver.resolve();
    final config = resolvedConfig.config;
    if (config == null) {
      throw const ConfigurationException(
        'Falta la configuración técnica experimental.',
      );
    }
    final deviceId = await secureStorage.getOrCreateDeviceId();
    BicimadDiagnostics.log('login', 'call_started');
    final session = await apiClient.login(
      email: email,
      password: password,
      passKey: config.passKey,
      xClientId: config.xClientId,
      deviceId: deviceId,
    );
    await secureStorage.saveSession(session: session, email: email);
    return session;
  }

  @override
  Future<MpassSession?> restoreSession() async {
    final stored = await secureStorage.readSession();
    if (stored == null) {
      return null;
    }
    if (stored.session.isExpiredAt(DateTime.now())) {
      await secureStorage.clearSession();
      throw const SessionExpiredException('La sesión ha caducado.');
    }
    return stored.session;
  }

  @override
  Future<List<Trip>> fetchTrips(MpassSession session, {int? page}) async {
    if (session.isExpiredAt(DateTime.now())) {
      await secureStorage.clearSession();
      throw const SessionExpiredException('La sesión ha caducado.');
    }

    final stored = await secureStorage.readSession();
    final email = stored?.email;
    if (email == null || email.isEmpty) {
      throw const SessionExpiredException('La sesión ha caducado.');
    }

    final deviceId = await secureStorage.getOrCreateDeviceId();
    if (page == null || _activeSyncUserId != session.idUser) {
      _activeSyncNif = await apiClient.fetchDsDn(
        session: session,
        email: email,
        deviceId: deviceId,
      );
      _activeSyncUserId = session.idUser;
    }
    final nif = _activeSyncNif;
    if (nif == null || nif.isEmpty) {
      throw const UnexpectedResponseException(
        'No se han podido preparar los viajes.',
      );
    }
    final trips = await apiClient.fetchTrips(
      session: session,
      email: email,
      nif: nif,
      deviceId: deviceId,
      page: page,
    );
    return [
      for (final trip in trips)
        mapper.toDomainTrip(trip: trip, userId: session.idUser),
    ];
  }

  @override
  Future<DateTime?> readLastAutomaticSyncAt() {
    return secureStorage.readLastAutomaticSyncAt();
  }

  @override
  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) {
    return secureStorage.saveLastAutomaticSyncAt(syncedAt);
  }

  @override
  Future<String?> readRememberedEmail() {
    return secureStorage.readRememberedEmail();
  }

  @override
  Future<void> clearSession() {
    _clearActiveSyncContext();
    return secureStorage.clearSession();
  }

  @override
  Future<void> disconnect() {
    _clearActiveSyncContext();
    return secureStorage.clearSession();
  }

  void _clearActiveSyncContext() {
    _activeSyncUserId = null;
    _activeSyncNif = null;
  }
}
