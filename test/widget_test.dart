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

  testWidgets('Botón Aleatorizar muestra diálogo de confirmación', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'cyber_fb_list': '[{"url":"https://facebook.com/groups/g1","status":"none"},{"url":"https://facebook.com/groups/g2","status":"none"}]',
      'cyber_fb_current_url': '',
    });
    await tester.pumpWidget(const CyberFBManagerApp());
    await tester.pumpAndSettle();

    // Tap en Aleatorizar
    await tester.tap(find.text('ALEATORIZAR'));
    await tester.pumpAndSettle();

    // Comprobar que aparece el diálogo de confirmación
    expect(find.text('ALEATORIZAR GRUPOS'), findsOneWidget);
    expect(find.text('CANCELAR'), findsOneWidget);

    // Cancelar diálogo
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();

    // El diálogo debe cerrarse
    expect(find.text('¿Deseas continuar?'), findsNothing);
  });

  testWidgets(
    'Configuración dinámica de Grupos por cuenta recalcula cuentas, valida mínimo 1 y permite restablecer a 25',
    (WidgetTester tester) async {
      final groupsJson = List.generate(
        25,
        (i) => '{"url":"https://facebook.com/groups/g${i + 1}","status":"none"}',
      ).join(',');

      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': '[$groupsJson]',
        'cyber_fb_current_url': '',
      });

      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      // Por defecto el límite es 25: 25 grupos = 1 cuenta (25/25)
      expect(find.textContaining('TOTAL: 25 GRUPOS • CUENTAS: 1'), findsOneWidget);
      expect(find.text('25/25'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('groups_per_account'), 25);

      // Abrir diálogo desde el botón "GRUPOS POR CUENTA"
      await tester.tap(find.text('GRUPOS POR CUENTA'));
      await tester.pumpAndSettle();

      expect(find.text('RESTABLECER A 25'), findsOneWidget);

      // Probar validación con valor inválido (0)
      final inputFinder = find.byKey(const Key('groups_per_account_input'));
      await tester.enterText(inputFinder, '0');
      await tester.tap(find.text('GUARDAR').last);
      await tester.pumpAndSettle();

      expect(find.text('MÍNIMO 1 GRUPO POR CUENTA'), findsWidgets);

      // Cambiar a 10 grupos por cuenta y guardar
      await tester.enterText(inputFinder, '10');
      await tester.tap(find.text('GUARDAR').last);
      await tester.pumpAndSettle();

      // Con 25 grupos y límite 10 -> 3 cuentas
      expect(find.textContaining('TOTAL: 25 GRUPOS • CUENTAS: 3'), findsOneWidget);
      expect(find.text('10/10'), findsWidgets);
      expect(prefs.getInt('groups_per_account'), 10);

      // Abrir nuevamente desde el botón "GRUPOS POR CUENTA" y restablecer a 25
      await tester.tap(find.text('GRUPOS POR CUENTA'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('RESTABLECER A 25'));
      await tester.pumpAndSettle();

      expect(find.textContaining('TOTAL: 25 GRUPOS • CUENTAS: 1'), findsOneWidget);
      expect(find.text('25/25'), findsOneWidget);
      expect(prefs.getInt('groups_per_account'), 25);
    },
  );
}
