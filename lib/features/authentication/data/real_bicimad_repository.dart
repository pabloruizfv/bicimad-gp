import '../../../core/errors/app_exception.dart';
import '../../trips/domain/trip.dart';
import '../domain/bicimad_repository.dart';
import '../domain/bicimad_session.dart';

class RealBicimadRepository implements BicimadRepository {
  static const _message =
      'La integracion real con BiciMAD esta pendiente: falta conocer el flujo '
      'de autenticacion, credenciales, tokens y endpoint de historial.';

  @override
  Future<BicimadSession> login({
    required String username,
    required String password,
  }) {
    throw const PendingIntegrationException(_message);
  }

  @override
  Future<List<Trip>> fetchTrips(BicimadSession session) {
    throw const PendingIntegrationException(_message);
  }

  @override
  Future<void> disconnect() {
    throw const PendingIntegrationException(_message);
  }
}
