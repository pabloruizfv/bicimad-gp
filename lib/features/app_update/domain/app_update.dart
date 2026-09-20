enum AppUpdateStatus {
  checking,
  current,
  available,
  required,
  downloading,
  awaitingPermission,
  installing,
  ready,
  error,
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.apkUrl,
    this.sha256,
  });

  final String currentVersion;
  final String latestVersion;
  final String minimumSupportedVersion;
  final Uri apkUrl;
  final String? sha256;
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    this.info,
    this.progress,
    this.errorMessage,
    this.isRequired = false,
  });

  const AppUpdateState.checking() : this(status: AppUpdateStatus.checking);

  final AppUpdateStatus status;
  final AppUpdateInfo? info;
  final double? progress;
  final String? errorMessage;
  final bool isRequired;

  bool get blocksApp => isRequired;
  bool get isBusy =>
      status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.awaitingPermission ||
      status == AppUpdateStatus.installing;
}

int compareVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  for (var i = 0; i < 3; i++) {
    final comparison = a[i].compareTo(b[i]);
    if (comparison != 0) return comparison;
  }
  return 0;
}

List<int> _versionParts(String value) {
  final parts = value.split('.');
  return List<int>.generate(
    3,
    (index) => int.tryParse(index < parts.length ? parts[index] : '') ?? 0,
  );
}
