import 'package:bicimad_social/core/errors/app_exception.dart';
import 'package:bicimad_social/shared/widgets/async_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('does not render private exception details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncStateView<int>(
          value: AsyncValue.error(
            StateError('fake-private-response'),
            StackTrace.empty,
          ),
          data: (value) => Text('$value'),
        ),
      ),
    );
    expect(find.textContaining('fake-private-response'), findsNothing);
    expect(find.text(safeErrorMessage(null)), findsOneWidget);
  });

  test('preserves app-owned actionable messages', () {
    expect(
      safeErrorMessage(const NetworkException('Error de conexión.')),
      'Error de conexión.',
    );
  });
}
