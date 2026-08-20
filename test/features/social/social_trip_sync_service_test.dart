import 'package:bicimad_social/features/social/application/social_trip_sync_service.dart';
import 'package:bicimad_social/features/trips/data/local_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_social_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  test(
    'descarga nube primero, combina con local y sube el historico completo',
    () async {
      final store = InMemorySecureKeyValueStore();
      final local = LocalCommunityRepository(store: store);
      await local.createOrRecoverUser(externalUserId: 'mpass-user');
      await local.replaceMyTrips([_trip('local-1', day: 2)]);
      final social = FakeSocialRepository(ownTrips: [_trip('cloud-1', day: 1)]);
      final service = SocialTripSyncService(
        socialRepository: social,
        localRepository: local,
      );

      final result = await service.synchronize(
        normalizedMpassEmail: 'pablo@example.com',
        mpassUserId: 'mpass-user',
      );

      expect(result.downloaded, 1);
      expect(result.uploaded, 2);
      expect(
        social.operations.indexOf('getOwnTrips'),
        lessThan(social.operations.indexOf('upsertOwnTrips')),
      );
      expect(
        social.uploadedTripBatches.single
            .map((trip) => trip.externalId)
            .toSet(),
        {'local-1', 'cloud-1'},
      );
    },
  );

  test('una segunda sincronizacion no duplica source_trip_id local', () async {
    final local = LocalCommunityRepository(
      store: InMemorySecureKeyValueStore(),
    );
    await local.createOrRecoverUser(externalUserId: 'mpass-user');
    final repeated = _trip('stable-trip-id', day: 1);
    await local.replaceMyTrips([repeated]);
    final social = FakeSocialRepository(ownTrips: [repeated]);
    final service = SocialTripSyncService(
      socialRepository: social,
      localRepository: local,
    );

    await service.synchronize(
      normalizedMpassEmail: 'pablo@example.com',
      mpassUserId: 'mpass-user',
    );

    expect(await local.getMyStages(), hasLength(1));
    expect(social.uploadedTripBatches.single, hasLength(1));
  });

  test('sube progresivamente un lote ya persistido', () async {
    final local = LocalCommunityRepository();
    await local.createOrRecoverUser(externalUserId: 'mpass-user');
    final social = FakeSocialRepository();
    final service = SocialTripSyncService(
      socialRepository: social,
      localRepository: local,
    );
    final batch = [_trip('page-trip', day: 3)];

    final uploaded = await service.pushTripBatch(
      normalizedMpassEmail: 'pablo@example.com',
      trips: batch,
    );

    expect(uploaded, 1);
    expect(social.uploadedTripBatches, [batch]);
  });

  test(
    'correo distinto bloquea la sincronizacion y cierra la sesion social',
    () async {
      final local = LocalCommunityRepository(
        store: InMemorySecureKeyValueStore(),
      );
      await local.createOrRecoverUser(externalUserId: 'mpass-user');
      final social = FakeSocialRepository(email: 'other@example.com');
      final service = SocialTripSyncService(
        socialRepository: social,
        localRepository: local,
      );

      await expectLater(
        service.synchronize(
          normalizedMpassEmail: 'pablo@example.com',
          mpassUserId: 'mpass-user',
        ),
        throwsA(isA<SocialIdentityMismatchException>()),
      );

      expect(social.signOutCalls, 1);
      expect(social.operations, isNot(contains('getOwnTrips')));
    },
  );
}

Trip _trip(String externalId, {required int day}) {
  return Trip(
    id: 'bicimad-$externalId',
    externalId: externalId,
    userId: 'mpass-user',
    originStationId: '1',
    originStationName: '1 - Origen',
    destinationStationId: '2',
    destinationStationName: '2 - Destino',
    startedAt: DateTime.utc(2026, 8, day, 10),
    durationSeconds: 600,
    isShared: true,
  );
}
