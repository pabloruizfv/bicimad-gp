import 'dart:convert';

import 'package:bicimad_social/features/trips/data/personal_trips_database.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  group('PersonalTripsDatabase', () {
    test('migra el JSON legacy, verifica IDs y elimina el original', () async {
      final store = InMemorySecureKeyValueStore();
      final database = PersonalTripsDatabase.inMemory();
      addTearDown(database.close);
      final trips = [_trip(1), _trip(2)];
      store.values[PersonalTripsDatabase.legacyTripsStorageKey] = jsonEncode([
        for (final trip in trips) _legacyJson(trip),
      ]);
      store.values[PersonalTripsDatabase.legacyKnownIdsStorageKey] = jsonEncode(
        {
          'user-1': ['discarded-source-id'],
        },
      );

      await database.migrateLegacyTrips(store);

      expect(await database.getTripsForUser('user-1'), hasLength(2));
      expect(
        await database.getKnownSourceIds('user-1'),
        containsAll(['trip-1', 'trip-2', 'discarded-source-id']),
      );
      expect(
        store.values,
        isNot(contains(PersonalTripsDatabase.legacyTripsStorageKey)),
      );
      expect(
        store.values,
        isNot(contains(PersonalTripsDatabase.legacyKnownIdsStorageKey)),
      );
    });

    test('la migracion es idempotente', () async {
      final store = InMemorySecureKeyValueStore();
      final database = PersonalTripsDatabase.inMemory();
      addTearDown(database.close);
      store.values[PersonalTripsDatabase.legacyTripsStorageKey] = jsonEncode([
        _legacyJson(_trip(1)),
      ]);

      await database.migrateLegacyTrips(store);
      store.values[PersonalTripsDatabase.legacyTripsStorageKey] = jsonEncode([
        _legacyJson(_trip(2)),
      ]);
      await database.migrateLegacyTrips(store);

      final stored = await database.getTripsForUser('user-1');
      expect(stored.map((trip) => trip.externalId), ['trip-1']);
      expect(
        store.values,
        isNot(contains(PersonalTripsDatabase.legacyTripsStorageKey)),
      );
    });

    test('un fallo no borra el JSON legacy', () async {
      final store = InMemorySecureKeyValueStore();
      final database = PersonalTripsDatabase.inMemory();
      addTearDown(database.close);
      store.values[PersonalTripsDatabase.legacyTripsStorageKey] = '{invalid';

      await expectLater(
        database.migrateLegacyTrips(store),
        throwsA(isA<FormatException>()),
      );

      expect(
        store.values[PersonalTripsDatabase.legacyTripsStorageKey],
        '{invalid',
      );
      expect(
        store.deletedKeys,
        isNot(contains(PersonalTripsDatabase.legacyTripsStorageKey)),
      );
    });

    test(
      'deduplica por usuario y trip_id y conserva valores no null',
      () async {
        final database = PersonalTripsDatabase.inMemory();
        addTearDown(database.close);
        await database.upsertTrips([
          _trip(1, bikeId: '00001234', tripCost: '1.25', distance: 842),
        ]);
        await database.upsertTrips([_trip(1)]);
        await database.upsertTrips([
          _trip(1, userId: 'user-2', bikeId: '00005678'),
        ]);

        final firstUser = await database.getTripsForUser('user-1');
        final secondUser = await database.getTripsForUser('user-2');
        expect(firstUser, hasLength(1));
        expect(firstUser.single.bikeId, '1234');
        expect(firstUser.single.tripCost, '1.25');
        expect(firstUser.single.directDistanceMeters, 842);
        expect(secondUser, hasLength(1));
        expect(secondUser.single.bikeId, '5678');
      },
    );

    test(
      'pagina por fecha y persiste 1000 viajes con bicicleta y precio',
      () async {
        final database = PersonalTripsDatabase.inMemory();
        addTearDown(database.close);
        final trips = [
          for (var index = 0; index < 1000; index++)
            _trip(index, bikeId: 'bike-$index', tripCost: '${index % 4}.5'),
        ];

        await database.upsertTrips(trips);
        final page = await database.getTripsForUser(
          'user-1',
          limit: 40,
          offset: 80,
        );

        expect(await database.countTrips('user-1'), 1000);
        expect(page, hasLength(40));
        expect(page.first.externalId, 'trip-919');
        expect(page.last.externalId, 'trip-880');
        expect(page.first.bikeId, 'bike-919');
        expect(page.first.tripCost, '3.5');
      },
    );

    test('consulta una ruta dirigida con paginacion', () async {
      final database = PersonalTripsDatabase.inMemory();
      addTearDown(database.close);
      await database.upsertTrips([
        _trip(1),
        _trip(2),
        _trip(3, origin: 'B', destination: 'A'),
      ]);

      final page = await database.getTripsForRoute(
        userId: 'user-1',
        originStationId: 'A',
        destinationStationId: 'B',
        limit: 1,
        offset: 1,
      );

      expect(page.single.externalId, 'trip-1');
    });

    test('no almacena viajes de ubicaciones descartadas', () async {
      final database = PersonalTripsDatabase.inMemory();
      addTearDown(database.close);
      final invalidOrigin = _trip(
        1,
      ).copyWith(originStationName: 'Bici mal anclada');
      final invalidDestination = _trip(
        2,
      ).copyWith(destinationStationName: 'Ubicación no permitida');

      await database.upsertTrips([invalidOrigin, invalidDestination, _trip(3)]);

      expect(
        (await database.getTripsForUser(
          'user-1',
        )).map((trip) => trip.externalId),
        ['trip-3'],
      );
      expect(
        await database.getKnownSourceIds('user-1'),
        containsAll(['trip-1', 'trip-2', 'trip-3']),
      );
    });

    test('elimina viajes e IDs conocidos solo del usuario indicado', () async {
      final database = PersonalTripsDatabase.inMemory();
      addTearDown(database.close);
      await database.upsertTrips([_trip(1), _trip(2, userId: 'user-2')]);
      await database.upsertKnownSourceIds('user-1', ['known-only']);

      await database.deleteUserData('user-1');

      expect(await database.getTripsForUser('user-1'), isEmpty);
      expect(await database.getKnownSourceIds('user-1'), isEmpty);
      expect(await database.getTripsForUser('user-2'), hasLength(1));
    });
  });
}

Trip _trip(
  int index, {
  String userId = 'user-1',
  String origin = 'A',
  String destination = 'B',
  String? bikeId,
  String? tripCost,
  double? distance,
}) {
  return Trip(
    id: 'trip-$index',
    externalId: 'trip-$index',
    userId: userId,
    originStationId: origin,
    originStationName: '$origin - Origin',
    destinationStationId: destination,
    destinationStationName: '$destination - Destination',
    startedAt: DateTime(2024, 1, 1).add(Duration(minutes: index)),
    durationSeconds: 600 + index,
    isShared: true,
    directDistanceMeters: distance,
    bikeId: bikeId,
    tripCost: tripCost,
  );
}

Map<String, Object?> _legacyJson(Trip trip) => {
  'id': trip.id,
  'externalId': trip.externalId,
  'userId': trip.userId,
  'originStationId': trip.originStationId,
  'originStationName': trip.originStationName,
  'destinationStationId': trip.destinationStationId,
  'destinationStationName': trip.destinationStationName,
  'startedAt': trip.startedAt.toIso8601String(),
  'durationSeconds': trip.durationSeconds,
  'isShared': trip.isShared,
  'originLatitude': trip.originLatitude,
  'originLongitude': trip.originLongitude,
  'destinationLatitude': trip.destinationLatitude,
  'destinationLongitude': trip.destinationLongitude,
  'directDistanceMeters': trip.directDistanceMeters,
  'bikeId': trip.bikeId,
  'tripCost': trip.tripCost,
  'pitStops': const [],
  'stageIds': const [],
  'stageDetails': const [],
};
