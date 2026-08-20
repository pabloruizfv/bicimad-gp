import 'package:bicimad_social/app/app.dart';
import 'package:bicimad_social/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('login solo pide email y contrasena', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(
            InMemorySecureKeyValueStore(),
          ),
          httpTransportProvider.overrideWithValue(QueuedHttpTransport()),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('bicimad GP'), findsOneWidget);
    expect(
      find.text('Introduce tu usuario y contraseña de BiciMAD'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.text('Introduce tu usuario y contraseña de BiciMAD'),
          )
          .maxLines,
      1,
    );
    expect(find.text('Email'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('passKey'), findsNothing);
    expect(find.text('X-ClientId'), findsNothing);
    expect(find.text('Configuración experimental'), findsNothing);
    expect(
      find.text('Consulta tus últimos viajes reales en modo experimental.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('login_bikes_logo')), findsOneWidget);
    expect(
      find.textContaining('La contraseña se usa para iniciar sesión'),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('login_credentials_info')));
    await tester.pumpAndSettle();

    expect(find.text('Uso de tus credenciales'), findsOneWidget);
    expect(
      find.textContaining('acceder a la información de tus viajes'),
      findsOneWidget,
    );
    expect(find.textContaining('No se almacena'), findsOneWidget);
  });

  testWidgets('no realiza peticiones si falta configuracion tecnica', (
    tester,
  ) async {
    final transport = QueuedHttpTransport();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(
            InMemorySecureKeyValueStore(),
          ),
          httpTransportProvider.overrideWithValue(transport),
        ],
        child: const BicimadSocialApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'fake@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'fake-password');
    await tester.tap(find.text('Entrar con MPass'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Falta la configuraci'), findsOneWidget);
    expect(find.textContaining('fake-password'), findsNothing);
    expect(transport.requests, isEmpty);
  });
}
