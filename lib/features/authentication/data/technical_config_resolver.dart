import '../../../core/config/bicimad_build_config.dart';
import '../../../core/diagnostics/bicimad_diagnostics.dart';
import '../../../core/errors/app_exception.dart';
import 'bicimad_secure_storage.dart';

enum TechnicalConfigSource { build, secureStorage, missing }

class ResolvedTechnicalConfig {
  const ResolvedTechnicalConfig({required this.config, required this.source});

  final TechnicalConfig? config;
  final TechnicalConfigSource source;

  bool get isConfigured => config != null;
}

class TechnicalConfigResolver {
  const TechnicalConfigResolver({
    required this.buildConfig,
    required this.secureStorage,
  });

  final BicimadBuildConfig buildConfig;
  final BicimadSecureStorage secureStorage;

  Future<ResolvedTechnicalConfig> resolve() async {
    BicimadDiagnostics.log('config', 'resolve_started');
    if (buildConfig.isComplete) {
      final resolved = ResolvedTechnicalConfig(
        config: TechnicalConfig(
          passKey: buildConfig.passKey,
          xClientId: buildConfig.xClientId,
        ),
        source: TechnicalConfigSource.build,
      );
      _emitDiagnostic(resolved);
      return resolved;
    }

    try {
      final stored = await secureStorage.readTechnicalConfig();
      if (stored != null) {
        final resolved = ResolvedTechnicalConfig(
          config: stored,
          source: TechnicalConfigSource.secureStorage,
        );
        _emitDiagnostic(resolved);
        return resolved;
      }
    } on SecureStorageException catch (error) {
      BicimadDiagnostics.error('config', error);
      rethrow;
    } on Object catch (error) {
      BicimadDiagnostics.error('config', error);
      throw const SecureStorageException(
        'No se ha podido acceder al almacenamiento seguro.',
      );
    }

    const resolved = ResolvedTechnicalConfig(
      config: null,
      source: TechnicalConfigSource.missing,
    );
    _emitDiagnostic(resolved);
    return resolved;
  }

  void _emitDiagnostic(ResolvedTechnicalConfig resolved) {
    BicimadDiagnostics.log('config', 'resolved', {
      'source': resolved.source.diagnosticName,
      'configured': resolved.isConfigured,
    });
  }
}

extension on TechnicalConfigSource {
  String get diagnosticName {
    return switch (this) {
      TechnicalConfigSource.build => 'build',
      TechnicalConfigSource.secureStorage => 'secure_storage',
      TechnicalConfigSource.missing => 'missing',
    };
  }
}
