class SupabaseBuildConfig {
  const SupabaseBuildConfig({
    required this.url,
    required this.publishableKey,
    required this.projectRef,
  });

  factory SupabaseBuildConfig.fromEnvironment() {
    return const SupabaseBuildConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      projectRef: String.fromEnvironment('SUPABASE_PROJECT_REF'),
    );
  }

  final String url;
  final String publishableKey;
  final String projectRef;

  bool get isComplete =>
      url.trim().isNotEmpty &&
      publishableKey.trim().isNotEmpty &&
      projectRef.trim().isNotEmpty;
}
