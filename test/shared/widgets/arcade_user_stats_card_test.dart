import 'package:bicimad_social/shared/widgets/arcade_user_stats_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desplaza solo nombres de estación que no caben', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 230,
            child: ColoredBox(
              color: Colors.blue,
              child: MostUsedStationBanner(
                stationName: '172 - Estación de tren de Delicias',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final scrolling = find.byKey(const ValueKey('most-used-station-scroll'));
    expect(scrolling, findsOneWidget);
    expect(
      tester.getSize(find.text('172 - Estación de tren de Delicias')).width,
      greaterThan(180),
    );
    expect(tester.widget<Transform>(scrolling).transform.getTranslation().x, 0);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester.widget<Transform>(scrolling).transform.getTranslation().x,
      lessThan(0),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          child: MostUsedStationBanner(stationName: 'Metro Lago'),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('most-used-station-scroll')),
      findsNothing,
    );
  });
}
