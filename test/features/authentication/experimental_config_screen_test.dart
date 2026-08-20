import 'package:bicimad_social/app/providers.dart';
import 'package:bicimad_social/core/config/bicimad_build_config.dart';
import 'package:bicimad_social/features/authentication/presentation/experimental_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('muestra configuracion incluida cuando procede de build', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadBuildConfigProvider.overrideWithValue(
            const BicimadBuildConfig(
              passKey: 'build-pass-key',
              xClientId: 'build-client-id',
            ),
          ),
          secureKeyValueStoreProvider.overrideWithValue(
            InMemorySecureKeyValueStore(),
          ),
        ],
        child: const MaterialApp(home: ExperimentalConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Configuración técnica incluida en esta compilación.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('build-pass-key'), findsNothing);
    expect(find.textContaining('build-client-id'), findsNothing);
  });

  testWidgets('conserva los campos cuando usa fallback de secure storage', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bicimadBuildConfigProvider.overrideWithValue(
            const BicimadBuildConfig(passKey: '', xClientId: ''),
          ),
          secureKeyValueStoreProvider.overrideWithValue(
            InMemorySecureKeyValueStore(),
          ),
        ],
        child: const MaterialApp(home: ExperimentalConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('passKey'), findsOneWidget);
    expect(find.text('X-ClientId'), findsOneWidget);
    expect(
      find.text('Falta la configuración técnica experimental.'),
      findsOneWidget,
    );
  });
}
