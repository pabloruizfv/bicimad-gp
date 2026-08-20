class BicimadBuildConfig {
  const BicimadBuildConfig({required this.passKey, required this.xClientId});

  factory BicimadBuildConfig.fromEnvironment() {
    return const BicimadBuildConfig(
      passKey: String.fromEnvironment('BICIMAD_PASS_KEY'),
      xClientId: String.fromEnvironment('BICIMAD_X_CLIENT_ID'),
    );
  }

  final String passKey;
  final String xClientId;

  bool get isComplete =>
      passKey.trim().isNotEmpty && xClientId.trim().isNotEmpty;

  bool get isEmpty => passKey.trim().isEmpty && xClientId.trim().isEmpty;

  bool get isPartial => !isComplete && !isEmpty;
}
