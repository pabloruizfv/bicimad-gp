import 'dart:async';
import 'dart:io';

import 'package:bicimad_social/app/app.dart';
import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/features/app_update/application/app_update_controller.dart';
import 'package:bicimad_social/features/app_update/data/github_update_repository.dart';
import 'package:bicimad_social/features/app_update/domain/app_update.dart';
import 'package:bicimad_social/features/authentication/domain/bicimad_repository.dart';
import 'package:bicimad_social/features/authentication/domain/mpass_session.dart';
import 'package:bicimad_social/features/trips/data/local_community_repository.dart';
import 'package:bicimad_social/features/trips/domain/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la descarga permanece visible si cambia la ruta de login', (
    tester,
  ) async {
    final restore = Completer<MpassSession?>();
    final bicimad = _GateRepository(restoreCompleter: restore);
    final updateRepository = _UpdateRepository();
    final installer = Completer<String?>();
    final controller = AppUpdateController(
      updateRepository,
      autoCheck: false,
      launchInstaller: (_, _) => installer.future,
    );
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('update_overlay_test_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final apk = File('${directory.path}/update.apk')..writeAsBytesSync([1]);
    await controller.check();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadRepositoryProvider.overrideWithValue(bicimad),
          communityRepositoryProvider.overrideWithValue(
            LocalCommunityRepository(),
          ),
          appUpdateControllerProvider.overrideWith((ref) => controller),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(OptionalUpdateDialog), findsOneWidget);
    await tester.tap(find.text('Actualizar'));
    await tester.pump();
    expect(find.text('Descargando actualización...'), findsOneWidget);

    restore.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Email'), findsOneWidget);
    expect(find.byType(OptionalUpdateDialog), findsOneWidget);
    expect(find.text('Descargando actualización...'), findsOneWidget);

    updateRepository.download.complete(apk);
    await tester.pump();
    installer.complete('cancelled');
    await tester.pump();
    expect(find.text('Instalar'), findsOneWidget);
  });

  testWidgets('no construye login mientras inicializa la recuperacion', (
    tester,
  ) async {
    final repository = _GateRepository(
      restoreCompleter: Completer<MpassSession?>(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadRepositoryProvider.overrideWithValue(repository),
          communityRepositoryProvider.overrideWithValue(
            LocalCommunityRepository(),
          ),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Preparando la aplicación…'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    repository.restoreCompleter!.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('error de red al restaurar conserva sesion y muestra acciones', (
    tester,
  ) async {
    final repository = _GateRepository(
      restoredSession: _session(),
      fetchError: const NetworkException('Error de conexión con BiciMAD.'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadRepositoryProvider.overrideWithValue(repository),
          communityRepositoryProvider.overrideWithValue(
            LocalCommunityRepository(),
          ),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No se ha podido recuperar tu sesión'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(repository.clearSessionCount, 0);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(repository.clearSessionCount, 1);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('fake@example.com'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
  });

  testWidgets('sesion caducada muestra login sin error de recuperacion', (
    tester,
  ) async {
    final repository = _GateRepository(
      restoreError: const SessionExpiredException('La sesión ha caducado.'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadRepositoryProvider.overrideWithValue(repository),
          communityRepositoryProvider.overrideWithValue(
            LocalCommunityRepository(),
          ),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('No se ha podido recuperar tu sesión'), findsNothing);
  });
}

class _UpdateRepository extends GithubUpdateRepository {
  final download = Completer<File>();

  @override
  Future<AppUpdateInfo> checkForUpdate() async => AppUpdateInfo(
    currentVersion: '1.3.5',
    latestVersion: '1.3.7',
    minimumSupportedVersion: '1.0.0',
    apkUrl: Uri.parse('https://github.com/example/update.apk'),
  );

  @override
  Future<File> downloadApk(
    AppUpdateInfo info,
    void Function(double progress) onProgress,
  ) => download.future;
}

MpassSession _session() {
  return MpassSession(
    accessToken: 'fake-token',
    idUser: 'fake-user-id',
    tokenSecExpiration: 3600,
    obtainedAt: DateTime.now(),
  );
}

class _GateRepository implements BicimadRepository {
  _GateRepository({
    this.restoreCompleter,
    this.restoredSession,
    this.restoreError,
    this.fetchError,
  });

  final Completer<MpassSession?>? restoreCompleter;
  final MpassSession? restoredSession;
  final Object? restoreError;
  final Object? fetchError;
  var clearSessionCount = 0;

  @override
  Future<void> clearSession() async {
    clearSessionCount++;
  }

  @override
  Future<void> disconnect() async {
    clearSessionCount++;
  }

  @override
  Future<List<Trip>> fetchTrips(MpassSession session, {int? page}) async {
    final error = fetchError;
    if (error != null) {
      throw error;
    }
    return [_trip()];
  }

  @override
  Future<MpassSession> login({
    required String email,
    required String password,
  }) async {
    return _session();
  }

  @override
  Future<DateTime?> readLastAutomaticSyncAt() async {
    return null;
  }

  @override
  Future<String?> readRememberedEmail() async {
    return 'fake@example.com';
  }

  @override
  Future<MpassSession?> restoreSession() async {
    final error = restoreError;
    if (error != null) {
      throw error;
    }
    final completer = restoreCompleter;
    if (completer != null) {
      return completer.future;
    }
    return restoredSession;
  }

  @override
  Future<void> saveLastAutomaticSyncAt(DateTime syncedAt) async {}
}

Trip _trip() {
  return Trip(
    id: 'trip-1',
    externalId: 'trip-1',
    userId: 'fake-user-id',
    originStationId: 'A',
    originStationName: 'Origen',
    destinationStationId: 'B',
    destinationStationName: 'Destino',
    startedAt: DateTime(2026, 8, 2, 10),
    durationSeconds: 600,
    isShared: true,
  );
}
