import '../../trips/domain/trip.dart';
import 'bicimad_session.dart';

abstract interface class BicimadRepository {
  Future<BicimadSession> login({
    required String username,
    required String password,
  });

  Future<List<Trip>> fetchTrips(BicimadSession session);

  Future<void> disconnect();
}
