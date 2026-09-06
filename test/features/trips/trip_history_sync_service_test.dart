import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/features/authentication/domain/bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:bicimad_social/features/trips/application/trip_history_sync_service.dart';
import 'package:bicimad_social/features/trips/data/local_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:bicimad_social/features/trips/domain/trip_history_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recorre paginas completas y termina con la ultima corta', () async {
    final repository = _FakePagedBicimadRepository([
      _trips(0, 30),
      _trips(30, 30),
      _trips(60, 5),
    ]);
    final local = await _localRepository();
    final service = _service(repository, local);

    final result = await service.synchronize(_session());

    expect(repository.requestedPages, [null, 1, 2]);
    expect(result.pagesFetched, 3);
    expect(result.tripsProcessed, 65);
    expect(result.stopReason, TripHistoryStopReason.historyExhausted);
    expect(await local.getMyStages(), hasLength(65));
    expect(await local.getCoverageIntervals(), hasLength(1));
    expect((await local.getTripHistorySyncState()).historyExhausted, isTrue);
  });

  test('un historico de una sola pagina corta queda agotado', () async {
    final repository = _FakePagedBicimadRepository([_trips(0, 8)]);
    final local = await _localRepository();

    final result = await _service(repository, local).synchronize(_session());

    expect(repository.requestedPages, [null]);
    expect(result.tripsProcessed, 8);
    expect(result.historyExhausted, isTrue);
  });

  test('detecta una pagina completamente repetida', () async {
    final firstPage = _trips(0, 30);
    final repository = _FakePagedBicimadRepository([firstPage, firstPage]);
    final local = await _localRepository();

    await expectLater(
      _service(repository, local).synchronize(_session()),
      throwsA(isA<TripHistorySyncException>()),
    );

    expect(await local.getMyStages(), hasLength(30));
    expect(
      (await local.getTripHistorySyncState()).lastRunStatus,
      TripHistoryRunStatus.interrupted,
    );
  });

  test('reintenta una vez el mismo GET tras error transitorio', () async {
    final repository = _FakePagedBicimadRepository([
      const NetworkException('fake transient error'),
      _trips(0, 4),
    ]);
    final local = await _localRepository();
    final delays = <Duration>[];
    final service = TripHistorySyncService(
      bicimadRepository: repository,
      communityRepository: local,
      pageDelay: Duration.zero,
      delay: (duration) async => delays.add(duration),
    );

    final result = await service.synchronize(_session());

    expect(repository.requestedPages, [null, null]);
    expect(delays, [const Duration(seconds: 2)]);
    expect(result.tripsProcessed, 4);
  });

  test('un error definitivo conserva las paginas ya guardadas', () async {
    final repository = _FakePagedBicimadRepository([
      _trips(0, 30),
      const NetworkException('fake first failure'),
      const NetworkException('fake final failure'),
    ]);
    final local = await _localRepository();

    await expectLater(
      _service(repository, local).synchronize(_session()),
      throwsA(isA<NetworkException>()),
    );

    expect(repository.requestedPages, [null, 1, 1]);
    expect(await local.getMyStages(), hasLength(30));
    final state = await local.getTripHistorySyncState();
    expect(state.historyExhausted, isFalse);
    expect(state.lastRunStatus, TripHistoryRunStatus.interrupted);
  });

  test('deduplica solapes parciales por trip_id', () async {
    final repository = _FakePagedBicimadRepository([
      _trips(0, 30),
      _trips(29, 30),
      _trips(59, 1),
    ]);
    final local = await _localRepository();

    final result = await _service(repository, local).synchronize(_session());

    expect(result.tripsProcessed, 60);
    expect(await local.getMyStages(), hasLength(60));
  });

  test(
    'incremental exige dos paginas completas conocidas consecutivas',
    () async {
      final local = await _localRepository();
      await local.replaceMyTrips(_trips(0, 120));
      await local.recordTripHistoryImport(
        TripHistoryImportRecord(
          state: TripHistorySyncState(
            historyExhausted: true,
            lastRunStatus: TripHistoryRunStatus.completed,
            updatedAt: DateTime(2026, 8, 1),
          ),
          overlapsKnownTrips: false,
          oldestImportedAt: DateTime(2026, 1, 1),
          newestImportedAt: DateTime(2026, 8, 1),
        ),
      );
      final repository = _FakePagedBicimadRepository([
        [_trip('new-a'), _trip('new-b'), ..._trips(0, 28)],
        _trips(28, 30),
        _trips(58, 30),
        _trips(88, 30),
      ]);

      final result = await _service(repository, local).synchronize(_session());

      expect(repository.requestedPages, [null, 1, 2]);
      expect(result.stopReason, TripHistoryStopReason.knownHistoryBoundary);
      expect(await local.getMyStages(), hasLength(122));
    },
  );

  test('una pagina conocida vuelve a enriquecer bike_id y trip_cost', () async {
    final local = await _localRepository();
    await local.replaceMyTrips([_trip('trip-0')]);
    final repository = _FakePagedBicimadRepository([
      [_trip('trip-0', bikeId: '1234', tripCost: '1.50')],
    ]);

    await _service(repository, local).synchronize(_session());

    final stored = (await local.getMyStages()).single;
    expect(stored.bikeId, '1234');
    expect(stored.tripCost, '1.50');
  });

  test('descarta ubicaciones invalidas sin subirlas ni contarlas', () async {
    final invalidOrigin = _trip(
      'bad-origin',
    ).copyWith(originStationName: 'Bici mal anclada');
    final invalidDestination = _trip(
      'bad-destination',
    ).copyWith(destinationStationName: 'Ubicación no permitida');
    final valid = _trip('valid');
    final repository = _FakePagedBicimadRepository([
      [invalidOrigin, valid, invalidDestination],
    ]);
    final local = await _localRepository();
    final persistedPages = <List<Trip>>[];

    final result = await _service(repository, local).synchronize(
      _session(),
      onPagePersisted: (trips) async => persistedPages.add(trips),
    );

    expect(result.tripsProcessed, 1);
    expect((await local.getMyStages()).map((trip) => trip.externalId), [
      'valid',
    ]);
    expect(persistedPages.single.map((trip) => trip.externalId), ['valid']);
    expect(
      await local.getKnownSourceTripIds(),
      containsAll(['bad-origin', 'bad-destination', 'valid']),
    );
  });
}

TripHistorySyncService _service(
  BicimadRepository repository,
  LocalCommunityRepository local,
) {
  return TripHistorySyncService(
    bicimadRepository: repository,
    communityRepository: local,
    pageDelay: Duration.zero,
    delay: (_) async {},
  );
}

Future<LocalCommunityRepository> _localRepository() async {
  final repository = LocalCommunityRepository();
  await repository.createOrRecoverUser(externalUserId: 'user-1');
  return repository;
}

List<Trip> _trips(int start, int count) {
  return [
    for (var index = start; index < start + count; index++)
      _trip('trip-$index'),
  ];
}

Trip _trip(String id, {String? bikeId, String? tripCost}) {
  final numericPart = int.tryParse(id.split('-').last) ?? 0;
  return Trip(
    id: 'bicimad-$id',
    externalId: id,
    userId: 'user-1',
    originStationId: '1',
    originStationName: '1 - Origen',
    destinationStationId: '2',
    destinationStationName: '2 - Destino',
    startedAt: DateTime(2026, 8, 1).subtract(Duration(hours: numericPart)),
    durationSeconds: 600,
    isShared: true,
    bikeId: bikeId,
    tripCost: tripCost,
  );
}

MpassSession _session() => MpassSession(
  accessToken: 'fake-token',
  idUser: 'user-1',
  tokenSecExpiration: 3600,
  obtainedAt: DateTime(2026, 8, 1),
);

class _FakePagedBicimadRepository implements BicimadRepository {
  _FakePagedBicimadRepository(List<Object> responses)
    : _responses = [...responses];

  final List<Object> _responses;
  final List<int?> requestedPages = [];

  @override
  Future<List<Trip>> fetchTrips(MpassSession session, {int? page}) async {
    requestedPages.add(page);
    final response = _responses.removeAt(0);
    if (response is Exception) {
      throw response;
    }
    return response as List<Trip>;
  }

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<MpassSession> login({
    required String email,
    required String password,
  }) async => _session();

  @override
  Future<DateTime?> readLastAutomaticSyncAt() async => null;

  @override
  Future<String?> readRememberedEmail() async => 'fake@example.test';

  @override
  Future<MpassSession?> restoreSession() async => _session();

  @override
  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) async {}
}
