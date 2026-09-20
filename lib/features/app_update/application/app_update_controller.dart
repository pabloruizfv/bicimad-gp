import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/github_update_repository.dart';
import '../domain/app_update.dart';

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    this._repository, {
    Future<String?> Function(File, AppUpdateInfo)? launchInstaller,
    bool autoCheck = true,
  }) : _launchInstaller = launchInstaller ?? _installApk,
       super(const AppUpdateState.checking()) {
    if (autoCheck) unawaited(check());
  }

  static const _installerChannel = MethodChannel('bicimad_gp/installer');
  final GithubUpdateRepository _repository;
  final Future<String?> Function(File, AppUpdateInfo) _launchInstaller;
  File? _downloadedApk;
  bool _checkInFlight = false;

  static Future<String?> _installApk(File file, AppUpdateInfo info) =>
      _installerChannel.invokeMethod<String>('installApk', {
        'path': file.path,
        'version': info.latestVersion,
      });

  Future<void> check() async {
    if (_checkInFlight ||
        state.isBusy ||
        state.status == AppUpdateStatus.ready) {
      return;
    }
    _checkInFlight = true;
    final wasRequired = state.isRequired;
    state = AppUpdateState(
      status: AppUpdateStatus.checking,
      info: state.info,
      isRequired: wasRequired,
    );
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
        isRequired: required,
      );
    } on Object catch (error) {
      state = AppUpdateState(
        status: AppUpdateStatus.error,
        errorMessage: error.toString(),
        info: state.info,
        isRequired: wasRequired,
      );
    } finally {
      _checkInFlight = false;
    }
  }

  Future<void> downloadAndInstall() async {
    final info = state.info;
    final isRequired = state.isRequired;
    final isAvailable =
        state.status == AppUpdateStatus.available ||
        (state.status == AppUpdateStatus.error && info != null);
    if (info == null || (!isRequired && !isAvailable)) return;
    _downloadedApk = null;
    state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      info: info,
      progress: 0,
      isRequired: isRequired,
    );
    try {
      final file = await _repository.downloadApk(info, (progress) {
        state = AppUpdateState(
          status: AppUpdateStatus.downloading,
          info: info,
          progress: progress,
          isRequired: isRequired,
        );
      });
      _downloadedApk = file;
      state = AppUpdateState(
        status: AppUpdateStatus.ready,
        info: info,
        progress: 1,
        isRequired: isRequired,
      );
      await installDownloaded();
    } on Object catch (error) {
      state = AppUpdateState(
        status: isRequired
            ? AppUpdateStatus.required
            : AppUpdateStatus.available,
        info: info,
        errorMessage: error.toString(),
        isRequired: isRequired,
      );
    }
  }

  Future<void> installDownloaded() async {
    final file = _downloadedApk;
    final info = state.info;
    if (file == null ||
        info == null ||
        state.status == AppUpdateStatus.installing) {
      return;
    }
    final isRequired = state.isRequired;
    if (!file.existsSync()) {
      _downloadedApk = null;
      state = AppUpdateState(
        status: isRequired
            ? AppUpdateStatus.required
            : AppUpdateStatus.available,
        info: info,
        isRequired: isRequired,
        errorMessage:
            'El APK descargado ya no está disponible. Descárgalo otra vez.',
      );
      return;
    }
    state = AppUpdateState(
      status: AppUpdateStatus.installing,
      info: info,
      progress: 1,
      isRequired: isRequired,
    );
    try {
      final result = await _launchInstaller(file, info);
      if (result == 'permission_required') {
        state = AppUpdateState(
          status: AppUpdateStatus.awaitingPermission,
          info: info,
          progress: 1,
          isRequired: isRequired,
        );
      } else if (result != 'installed') {
        state = AppUpdateState(
          status: AppUpdateStatus.ready,
          info: info,
          progress: 1,
          isRequired: isRequired,
          errorMessage: 'La instalación no se ha completado.',
        );
      }
    } on PlatformException catch (error) {
      final invalidFile =
          error.code == 'INVALID_APK' || error.code == 'MISSING_APK';
      if (invalidFile) _downloadedApk = null;
      state = AppUpdateState(
        status: invalidFile
            ? isRequired
                  ? AppUpdateStatus.required
                  : AppUpdateStatus.available
            : AppUpdateStatus.ready,
        info: info,
        progress: 1,
        isRequired: isRequired,
        errorMessage: error.code,
      );
    } on Object catch (error) {
      state = AppUpdateState(
        status: AppUpdateStatus.ready,
        info: info,
        progress: 1,
        isRequired: isRequired,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> onResume() async {
    if (state.status == AppUpdateStatus.awaitingPermission) {
      try {
        final allowed = await _installerChannel.invokeMethod<bool>(
          'canInstallApk',
        );
        if (allowed == true) await installDownloaded();
      } on PlatformException catch (error) {
        state = AppUpdateState(
          status: AppUpdateStatus.ready,
          info: state.info,
          isRequired: state.isRequired,
          errorMessage: error.code,
        );
      }
    } else {
      await check();
    }
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}
