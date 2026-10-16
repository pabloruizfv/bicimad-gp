enum AppUpdateStatus { checking, current, available, error }

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String minimumSupportedVersion;
  final Uri releaseUrl;
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    this.info,
    this.errorMessage,
    this.isUnsupported = false,
  });

  const AppUpdateState.checking() : this(status: AppUpdateStatus.checking);

  final AppUpdateStatus status;
  final AppUpdateInfo? info;
  final String? errorMessage;
  final bool isUnsupported;
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
