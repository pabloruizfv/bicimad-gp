import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/github_update_repository.dart';
import '../domain/app_update.dart';

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._repository)
    : super(const AppUpdateState.checking()) {
    unawaited(check());
  }

  static const _installerChannel = MethodChannel('bicimad_gp/installer');
  final GithubUpdateRepository _repository;

  Future<void> check() async {
    if (state.status == AppUpdateStatus.downloading) return;
    state = const AppUpdateState.checking();
    try {
      final info = await _repository.checkForUpdate();
      final required =
          compareVersions(info.currentVersion, info.minimumSupportedVersion) <
          0;
      final newerVersion =
          compareVersions(info.latestVersion, info.currentVersion) > 0;
      state = AppUpdateState(
        status: required
            ? AppUpdateStatus.required
            : newerVersion
            ? AppUpdateStatus.available
            : AppUpdateStatus.current,
        info: info,
      );
    } on Object catch (error) {
      state = AppUpdateState(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> downloadAndInstall() async {
    final info = state.info;
    final isRequired = state.status == AppUpdateStatus.required;
    final isAvailable = state.status == AppUpdateStatus.available;
    if (info == null || (!isRequired && !isAvailable)) return;
    state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      info: info,
      progress: 0,
    );
    try {
      final file = await _repository.downloadApk(info, (progress) {
        state = AppUpdateState(
          status: AppUpdateStatus.downloading,
          info: info,
          progress: progress,
        );
      });
      state = AppUpdateState(
        status: AppUpdateStatus.ready,
        info: info,
        progress: 1,
      );
      await _installerChannel.invokeMethod<void>('installApk', file.path);
    } on Object catch (error) {
      state = AppUpdateState(
        status: isRequired
            ? AppUpdateStatus.required
            : AppUpdateStatus.available,
        info: info,
        errorMessage: error.toString(),
      );
    }
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}
