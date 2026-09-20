import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bicimad_social/app/app.dart';
import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/app_update/application/app_update_controller.dart';
import 'package:bicimad_social/features/app_update/data/github_update_repository.dart';
import 'package:bicimad_social/features/app_update/domain/app_update.dart';

final _update = AppUpdateInfo(
  currentVersion: '1.3.5',
  latestVersion: '1.3.7',
  minimumSupportedVersion: '1.0.0',
  apkUrl: Uri.parse('https://github.com/example/update.apk'),
);

Future<File> _testApk() async {
  final directory = await Directory.systemTemp.createTemp('update_test_');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/update.apk').writeAsBytes([1]);
}

class _Repository extends GithubUpdateRepository {
  _Repository(this.info);

  final AppUpdateInfo info;
  final download = Completer<File>();
  int checks = 0;
  int downloads = 0;
  void Function(double)? progress;

  @override
  Future<AppUpdateInfo> checkForUpdate() async {
    checks++;
    return info;
  }

  @override
  Future<File> downloadApk(
    AppUpdateInfo info,
    void Function(double progress) onProgress,
  ) {
    downloads++;
    progress = onProgress;
    return download.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download survives resume and installs only after completion', () async {
    final apk = await _testApk();
    final repository = _Repository(_update);
    final installer = Completer<String?>();
    final installerStarted = Completer<void>();
    var installs = 0;
    final controller = AppUpdateController(
      repository,
      autoCheck: false,
      launchInstaller: (file, info) {
        installs++;
        expect(file.path, endsWith('update.apk'));
        expect(info.latestVersion, '1.3.7');
        installerStarted.complete();
        return installer.future;
      },
    );
    addTearDown(controller.dispose);

    await controller.check();
    expect(controller.state.status, AppUpdateStatus.available);
    final updating = controller.downloadAndInstall();
    expect(controller.state.status, AppUpdateStatus.downloading);
    repository.progress!(0.4);
    expect(controller.state.progress, 0.4);
    await controller.onResume();
    expect(repository.checks, 1);
    expect(installs, 0);

    repository.download.complete(apk);
    await installerStarted.future;
    expect(controller.state.status, AppUpdateStatus.installing);
    expect(installs, 1);
    installer.complete('cancelled');
    await updating;
    expect(controller.state.status, AppUpdateStatus.ready);
    expect(controller.state.errorMessage, isNotNull);
    expect(repository.downloads, 1);
  });

  test(
    'resume checks for a newer release while an optional update is offered',
    () async {
      final repository = _Repository(_update);
      final controller = AppUpdateController(repository, autoCheck: false);
      addTearDown(controller.dispose);

      await controller.check();
      await controller.onResume();
      expect(repository.checks, 2);
      expect(controller.state.status, AppUpdateStatus.available);
    },
  );

  test('required update stays blocking through download and retry', () async {
    final apk = await _testApk();
    final repository = _Repository(
      AppUpdateInfo(
        currentVersion: '1.3.5',
        latestVersion: '1.3.7',
        minimumSupportedVersion: '1.3.6',
        apkUrl: _update.apkUrl,
      ),
    );
    var installs = 0;
    final controller = AppUpdateController(
      repository,
      autoCheck: false,
      launchInstaller: (_, _) async {
        installs++;
        return installs == 1 ? 'permission_required' : 'cancelled';
      },
    );
    addTearDown(controller.dispose);

    await controller.check();
    expect(controller.state.blocksApp, isTrue);
    final updating = controller.downloadAndInstall();
    expect(controller.state.blocksApp, isTrue);
    repository.download.complete(apk);
    await updating;
    expect(controller.state.status, AppUpdateStatus.awaitingPermission);
    expect(controller.state.blocksApp, isTrue);
    await controller.installDownloaded();
    expect(controller.state.status, AppUpdateStatus.ready);
    expect(controller.state.blocksApp, isTrue);
    expect(repository.downloads, 1);
    expect(installs, 2);
  });

  test('permission return retries installer without a new download', () async {
    final apk = await _testApk();
    const channel = MethodChannel('bicimad_gp/installer');
    var allowed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'canInstallApk');
          return allowed;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final repository = _Repository(_update);
    var installs = 0;
    final controller = AppUpdateController(
      repository,
      autoCheck: false,
      launchInstaller: (_, _) async {
        installs++;
        return installs == 1 ? 'permission_required' : 'cancelled';
      },
    );
    addTearDown(controller.dispose);
    await controller.check();
    final updating = controller.downloadAndInstall();
    repository.download.complete(apk);
    await updating;
    await controller.onResume();
    expect(installs, 1);
    allowed = true;
    await controller.onResume();
    expect(installs, 2);
    expect(repository.downloads, 1);
  });

  test(
    'invalid APK returns to download instead of retrying installation',
    () async {
      final apk = await _testApk();
      final repository = _Repository(_update);
      final controller = AppUpdateController(
        repository,
        autoCheck: false,
        launchInstaller: (_, _) async =>
            throw PlatformException(code: 'INVALID_APK'),
      );
      addTearDown(controller.dispose);
      await controller.check();
      final updating = controller.downloadAndInstall();
      repository.download.complete(apk);
      await updating;

      expect(controller.state.status, AppUpdateStatus.available);
      expect(controller.state.errorMessage, 'INVALID_APK');
      await controller.downloadAndInstall();
      expect(repository.downloads, 2);
    },
  );

  testWidgets('update dialog stays open and blocks back during download', (
    tester,
  ) async {
    final apk = (await tester.runAsync(_testApk))!;
    final repository = _Repository(_update);
    final installer = Completer<String?>();
    final controller = AppUpdateController(
      repository,
      autoCheck: false,
      launchInstaller: (_, _) => installer.future,
    );
    await controller.check();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const OptionalUpdateDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actualizar'));
    await tester.pump();
    expect(find.text('Descargando actualización...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(OptionalUpdateDialog), findsOneWidget);

    repository.download.complete(apk);
    await tester.pump();
    expect(find.text('Abriendo el instalador...'), findsOneWidget);
    installer.complete('cancelled');
    await tester.pump();
    expect(find.text('Instalar'), findsOneWidget);
  });
}
