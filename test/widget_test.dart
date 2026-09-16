import 'package:flutter_test/flutter_test.dart';
import 'package:fb_manager/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';

void main() {
  testWidgets('Cyber FB Manager Pro smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CyberFBManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('CYBER FB MANAGER PRO'), findsOneWidget);
    expect(find.text('AÑADIR'), findsOneWidget);
    expect(find.text('IR AL ACTUAL'), findsOneWidget);

    // FloatingActionButton con icono de mira / enfoque
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('FloatingActionButton y botón Ir al Actual responden al tap', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'cyber_fb_list': '[{"url":"https://facebook.com/groups/g1","status":"none"}]',
      'cyber_fb_current_url': 'https://facebook.com/groups/g1',
    });
    await tester.pumpWidget(const CyberFBManagerApp());
    await tester.pumpAndSettle();

    // Tap en el FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Tap en el botón Ir al actual del panel superior
    await tester.tap(find.text('IR AL ACTUAL'));
    await tester.pumpAndSettle();

    expect(find.text('ENFOCANDO...'), findsOneWidget);
  });
}
