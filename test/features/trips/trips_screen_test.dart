import 'package:bicimad_social/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows imported trips after simulated login and display name', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: BicimadSocialApp()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'pablo@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('Entrar con MPass'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre visible'), findsWidgets);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Mis viajes'), findsOneWidget);
    expect(
      find.textContaining('Última sincronización simulada'),
      findsOneWidget,
    );
    expect(find.text('Manuel Becerra → Felipe II'), findsWidgets);
    expect(find.text('Récord personal'), findsWidgets);
  });
}
