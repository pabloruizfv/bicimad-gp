import 'package:bicimad_social/shared/widgets/arcade_user_stats_card.dart';
import 'package:bicimad_social/shared/widgets/head_to_head_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renderiza el SVG especifico de Cara a cara', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: HeadToHeadIcon(width: 112, height: 56)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final svg = tester.widget<SvgPicture>(
      find.byKey(const ValueKey('head-to-head-svg')),
    );
    expect(svg.width, 112);
    expect(svg.height, 56);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el acceso de perfil es un boton compacto solo con el icono', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: HeadToHeadButton(onTap: () => pressed = true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = find.byType(HeadToHeadIcon);
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon), const Size(72, 34));
    expect(find.text('Ver cara a cara'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('head-to-head-action')));
    expect(pressed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
