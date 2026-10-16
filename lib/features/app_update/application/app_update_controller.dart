import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/github_update_repository.dart';
import '../domain/app_update.dart';

typedef ReleasePageLauncher = Future<bool> Function(Uri url);

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    this._repository, {
    ReleasePageLauncher? launchReleasePage,
    bool autoCheck = true,
  }) : _launchReleasePage = launchReleasePage ?? _openInBrowser,
       super(const AppUpdateState.checking()) {
    if (autoCheck) unawaited(check());
  }

  final GithubUpdateRepository _repository;
  final ReleasePageLauncher _launchReleasePage;
  bool _checkInFlight = false;

  static Future<bool> _openInBrowser(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  Future<void> check() async {
    if (_checkInFlight) return;
    _checkInFlight = true;
    final wasUnsupported = state.isUnsupported;
    state = AppUpdateState(
      status: AppUpdateStatus.checking,
      info: state.info,
      isUnsupported: wasUnsupported,
    );
    try {
      final info = await _repository.checkForUpdate();
      final unsupported =
          compareVersions(info.currentVersion, info.minimumSupportedVersion) <
          0;
      final newerVersion =
          compareVersions(info.latestVersion, info.currentVersion) > 0;
      state = AppUpdateState(
        status: newerVersion || unsupported
            ? AppUpdateStatus.available
            : AppUpdateStatus.current,
        info: info,
        isUnsupported: unsupported,
      );
    } on Object catch (error) {
      state = AppUpdateState(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
        info: state.info,
        isUnsupported: wasUnsupported,
      );
    } finally {
      _checkInFlight = false;
    }
  }

  Future<bool> openReleasePage() async {
    final url = state.info?.releaseUrl;
    if (url == null) return false;
    try {
      return await _launchReleasePage(url);
    } on Object {
      return false;
    }
  }

  Future<void> onResume() => check();

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}
