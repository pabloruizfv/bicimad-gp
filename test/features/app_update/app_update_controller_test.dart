import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bicimad_social/app/app.dart';
import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/features/app_update/application/app_update_controller.dart';
import 'package:bicimad_social/features/app_update/data/github_update_repository.dart';
import 'package:bicimad_social/features/app_update/domain/app_update.dart';

final _releaseUrl = Uri.parse(
  'https://github.com/pabloruizfv/bicimad-gp/releases/tag/v1.0.2',
);

AppUpdateInfo _update({String minimumSupportedVersion = '1.0.0'}) =>
    AppUpdateInfo(
      currentVersion: '1.0.1',
      latestVersion: '1.0.2',
      minimumSupportedVersion: minimumSupportedVersion,
      releaseUrl: _releaseUrl,
    );

class _Repository extends GithubUpdateRepository {
  _Repository(this.info);

  final AppUpdateInfo info;
  int checks = 0;

  @override
  Future<AppUpdateInfo> checkForUpdate() async {
    checks++;
    return info;
  }
}

void main() {
  test('detects a newer release without blocking the app', () async {
    final repository = _Repository(_update());
    final controller = AppUpdateController(repository, autoCheck: false);
    addTearDown(controller.dispose);

    await controller.check();

    expect(controller.state.status, AppUpdateStatus.available);
    expect(controller.state.isUnsupported, isFalse);
  });

  test(
    'an unsupported version remains usable and gets a stronger warning',
    () async {
      final repository = _Repository(_update(minimumSupportedVersion: '1.0.2'));
      final controller = AppUpdateController(repository, autoCheck: false);
      addTearDown(controller.dispose);

      await controller.check();

      expect(controller.state.status, AppUpdateStatus.available);
      expect(controller.state.isUnsupported, isTrue);
    },
  );

  test('resume checks GitHub again while an update is available', () async {
    final repository = _Repository(_update());
    final controller = AppUpdateController(repository, autoCheck: false);
    addTearDown(controller.dispose);

    await controller.check();
    await controller.onResume();

    expect(repository.checks, 2);
    expect(controller.state.status, AppUpdateStatus.available);
  });

  test('opens the GitHub release page in the external launcher', () async {
    final repository = _Repository(_update());
    Uri? openedUrl;
    final controller = AppUpdateController(
      repository,
      autoCheck: false,
      launchReleasePage: (url) async {
        openedUrl = url;
        return true;
      },
    );
    addTearDown(controller.dispose);
    await controller.check();

    expect(await controller.openReleasePage(), isTrue);
    expect(openedUrl, _releaseUrl);
  });

  testWidgets('dialog links to GitHub and explains unsupported versions', (
    tester,
  ) async {
    final repository = _Repository(_update(minimumSupportedVersion: '1.0.2'));
    var launches = 0;
    final controller = AppUpdateController(
      repository,
      autoCheck: false,
      launchReleasePage: (_) async {
        launches++;
        return true;
      },
    );
    await controller.check();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: Scaffold(body: OptionalUpdateDialog())),
      ),
    );

    expect(find.text('Nueva versión disponible'), findsOneWidget);
    expect(find.textContaining('algunas funciones'), findsOneWidget);
    expect(find.text('Ir a GitHub'), findsOneWidget);

    await tester.tap(find.text('Ir a GitHub'));
    await tester.pump();
    expect(launches, 1);
  });
}
