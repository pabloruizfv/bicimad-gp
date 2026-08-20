import 'package:bicimad_social/shared/widgets/menu_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mantiene titulo y muestra logo no interactivo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(appBar: MenuAppBar(title: Text('Mis viajes'))),
      ),
    );

    expect(find.text('Mis viajes'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_app_bar_logo')), findsOneWidget);
  });
}
