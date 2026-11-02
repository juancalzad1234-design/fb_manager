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

  testWidgets('FloatingActionButton y botón Ir al Actual responden al tap', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'cyber_fb_list':
          '[{"url":"https://facebook.com/groups/g1","status":"none"}]',
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

  testWidgets('Botón Aleatorizar muestra diálogo de confirmación', (
    WidgetTester tester,
  ) async {
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
        (i) =>
            '{"url":"https://facebook.com/groups/g${i + 1}","status":"none"}',
      ).join(',');

      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': '[$groupsJson]',
        'cyber_fb_current_url': '',
      });

      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      // Por defecto el límite es 25: 25 grupos = 1 cuenta (25/25)
      expect(
        find.textContaining('TOTAL: 25 GRUPOS • CUENTAS: 1'),
        findsOneWidget,
      );
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
      expect(
        find.textContaining('TOTAL: 25 GRUPOS • CUENTAS: 3'),
        findsOneWidget,
      );
      expect(find.text('10/10'), findsWidgets);
      expect(prefs.getInt('groups_per_account'), 10);

      // Abrir nuevamente desde el botón "GRUPOS POR CUENTA" y restablecer a 25
      await tester.tap(find.text('GRUPOS POR CUENTA'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('RESTABLECER A 25'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('TOTAL: 25 GRUPOS • CUENTAS: 1'),
        findsOneWidget,
      );
      expect(find.text('25/25'), findsOneWidget);
      expect(prefs.getInt('groups_per_account'), 25);
    },
  );

  group('Contador de misión, importación y UX', () {
    String lista(List<String> ids, {Map<String, String> estados = const {}}) {
      return '[${ids.map((id) => '{"url":"https://facebook.com/groups/$id/","status":"${estados[id] ?? 'none'}"}').join(',')}]';
    }

    Future<void> bigSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> abrirTexto(WidgetTester tester) async {
      await tester.tap(find.text('DATOS ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEXTO / IMPORTAR'));
      await tester.pumpAndSettle();
    }

    testWidgets('el contador se carga desde el almacenamiento', (tester) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({'cyber_fb_mission_count': 7});
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('MISIÓN: 7/25 AÑADIDOS'), findsOneWidget);
    });

    testWidgets('añadir un grupo guarda el contador y la lista', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'https://m.facebook.com/groups/nuevo1?ref=share',
      );
      await tester.tap(find.text('AÑADIR'));
      await tester.pumpAndSettle();

      expect(find.textContaining('MISIÓN: 1/25 AÑADIDOS'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('cyber_fb_mission_count'), 1);
      expect(
        prefs.getString('cyber_fb_list'),
        contains('https://facebook.com/groups/nuevo1/'),
      );
    });

    testWidgets('rechaza repetidos y enlaces inválidos con mensaje visible', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(['g1']),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'https://www.facebook.com/share/g/g1/?mibextid=x',
      );
      await tester.tap(find.text('AÑADIR'));
      await tester.pumpAndSettle();

      expect(find.text('GRUPO REPETIDO'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('cyber_fb_mission_count') ?? 0, 0);
    });

    testWidgets(
      'al llegar a la meta el contador vuelve a 0 y la misión se celebra',
      (tester) async {
        await bigSurface(tester);
        SharedPreferences.setMockInitialValues({
          'groups_per_account': 3,
          'cyber_fb_mission_count': 2,
          'cyber_fb_list': lista(['g1', 'g2']),
        });
        await tester.pumpWidget(const CyberFBManagerApp());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'https://facebook.com/groups/g3',
        );
        await tester.tap(find.text('AÑADIR'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('MISIÓN CUMPLIDA'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('cyber_fb_mission_count'), 0);

        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(find.textContaining('MISIÓN CUMPLIDA'), findsNothing);
        expect(find.textContaining('MISIÓN: 0/3 AÑADIDOS'), findsOneWidget);
      },
    );

    testWidgets('el botón de reinicio pone el contador a 0', (tester) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({'cyber_fb_mission_count': 9});
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('↺'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REINICIAR'));
      await tester.pumpAndSettle();

      expect(find.textContaining('MISIÓN: 0/25 AÑADIDOS'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('cyber_fb_mission_count'), 0);
    });

    testWidgets(
      'añadir un enlace con un grupo malo lo reemplaza y actualiza el actual',
      (tester) async {
        await bigSurface(tester);
        SharedPreferences.setMockInitialValues({
          'cyber_fb_list': lista(['g1', 'g2'], estados: {'g2': 'bad'}),
          'cyber_fb_current_url': 'https://facebook.com/groups/g2/',
        });
        await tester.pumpWidget(const CyberFBManagerApp());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'https://facebook.com/groups/nuevo',
        );
        await tester.tap(find.text('AÑADIR'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('REEMPLAZADO EN CUENTA 1 (#2)'),
          findsOneWidget,
        );
        final prefs = await SharedPreferences.getInstance();
        final guardada = prefs.getString('cyber_fb_list')!;
        expect(guardada, contains('groups/nuevo/'));
        expect(guardada, isNot(contains('groups/g2/')));
        expect(
          prefs.getString('cyber_fb_current_url'),
          'https://facebook.com/groups/nuevo/',
        );
      },
    );

    testWidgets('pegar varios enlaces a la vez los añade omitiendo repetidos', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(['g1']),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'https://facebook.com/groups/g1\nhttps://facebook.com/groups/aa\nhttps://facebook.com/groups/bb',
      );
      await tester.tap(find.text('AÑADIR'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AÑADIDOS: 2 · REPETIDOS: 1'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('cyber_fb_mission_count'), 2);
      expect(prefs.getString('cyber_fb_list'), contains('groups/bb/'));
    });

    testWidgets(
      'importar con Fusionar combina sin duplicar y conserva calificaciones',
      (tester) async {
        await bigSurface(tester);
        SharedPreferences.setMockInitialValues({
          'cyber_fb_list': lista(['g1', 'g2'], estados: {'g1': 'good'}),
        });
        await tester.pumpWidget(const CyberFBManagerApp());
        await tester.pumpAndSettle();

        await abrirTexto(tester);
        final campo = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(
          campo,
          '{"data":{"grupos":[{"link":"https://m.facebook.com/groups/g1/?x=1","estado":"malo"},'
          '{"enlace":"facebook.com/groups/g3","estado":"bueno"}]}}',
        );
        await tester.tap(find.text('IMPORTAR'));
        await tester.pumpAndSettle();

        expect(find.text('IMPORTAR DATOS'), findsOneWidget);
        expect(find.textContaining('NUEVOS: 1'), findsOneWidget);
        expect(find.textContaining('REPETIDOS: 1'), findsOneWidget);

        await tester.tap(find.text('FUSIONAR'));
        await tester.pumpAndSettle();

        expect(find.textContaining('FUSIONADO: +1 NUEVOS'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        final guardada = prefs.getString('cyber_fb_list')!;
        expect(guardada, contains('groups/g3/'));
        expect(
          guardada,
          contains('{"url":"https://facebook.com/groups/g1/","status":"good"}'),
        );
        expect(prefs.getString('cyber_fb_list_backup'), isNotNull);
        expect(prefs.getInt('cyber_fb_mission_count') ?? 0, 0);
      },
    );

    testWidgets('importar con Reemplazar y luego Deshacer restaura la lista', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(['g1', 'g2']),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await abrirTexto(tester);
      final campo = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        campo,
        'https://facebook.com/groups/solo1\nhttps://facebook.com/groups/solo2',
      );
      await tester.tap(find.text('IMPORTAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REEMPLAZAR'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cyber_fb_list'), contains('solo1'));
      expect(prefs.getString('cyber_fb_list'), isNot(contains('groups/g1/')));

      await tester.tap(find.text('DESHACER'));
      await tester.pumpAndSettle();

      expect(prefs.getString('cyber_fb_list'), contains('groups/g1/'));
      expect(prefs.getString('cyber_fb_list'), isNot(contains('solo1')));
    });

    testWidgets('contenido sin grupos muestra aviso y no abre el resumen', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await abrirTexto(tester);
      final campo = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(campo, '{"nada": "util"}');
      await tester.tap(find.text('IMPORTAR'));
      await tester.pumpAndSettle();

      expect(find.text('NO SE ENCONTRARON GRUPOS'), findsOneWidget);
      expect(find.text('IMPORTAR DATOS'), findsNothing);
    });

    testWidgets('borrar un grupo y deshacer lo recupera', (tester) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(['g1', 'g2']),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('✕').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('BORRAR'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cyber_fb_list'), isNot(contains('groups/g1/')));
      expect(find.text('ELIMINADO'), findsOneWidget);

      await tester.tap(find.text('DESHACER'));
      await tester.pumpAndSettle();

      expect(prefs.getString('cyber_fb_list'), contains('groups/g1/'));
      expect(prefs.getString('cyber_fb_list'), contains('groups/g2/'));
    });

    testWidgets('el filtro por estado oculta el resto de grupos', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(['g1', 'g2', 'g3'], estados: {'g2': 'good'}),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      expect(find.text('https://facebook.com/groups/g1/'), findsOneWidget);

      await tester.tap(find.text('BIEN').first); // chip del filtro
      await tester.pumpAndSettle();

      expect(find.text('https://facebook.com/groups/g1/'), findsNothing);
      expect(find.text('https://facebook.com/groups/g2/'), findsOneWidget);

      await tester.tap(find.text('TODOS'));
      await tester.pumpAndSettle();
      expect(find.text('https://facebook.com/groups/g1/'), findsOneWidget);
    });

    testWidgets('la búsqueda filtra por texto de la URL', (tester) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(['alfa', 'beta']),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '').last, 'bet');
      await tester.pumpAndSettle();

      expect(find.text('https://facebook.com/groups/alfa/'), findsNothing);
      expect(find.text('https://facebook.com/groups/beta/'), findsOneWidget);
    });

    testWidgets('los contadores por estado se muestran en el encabezado', (
      tester,
    ) async {
      await bigSurface(tester);
      SharedPreferences.setMockInitialValues({
        'cyber_fb_list': lista(
          ['a', 'b', 'c'],
          estados: {'a': 'good', 'b': 'bad'},
        ),
      });
      await tester.pumpWidget(const CyberFBManagerApp());
      await tester.pumpAndSettle();

      // Total y cabecera de cuenta (mismos contadores)
      expect(find.textContaining('✔1  ~0  ✘1  ?1'), findsNWidgets(2));
    });
  });
}
