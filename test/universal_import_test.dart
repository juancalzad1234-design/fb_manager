import 'dart:convert';

import 'package:fb_manager/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UniversalImporter', () {
    test('formato nativo de la app se conserva', () {
      final r = UniversalImporter.parse(
        jsonEncode([
          {'url': 'https://facebook.com/groups/a/', 'status': 'good'},
          {'url': 'https://facebook.com/groups/b/', 'status': 'bad'},
          {'url': 'https://facebook.com/groups/c/', 'status': 'none'},
        ]),
      );
      expect(r.formato, 'json-lista');
      expect(r.items.map((g) => g.url).toList(), [
        'https://facebook.com/groups/a/',
        'https://facebook.com/groups/b/',
        'https://facebook.com/groups/c/',
      ]);
      expect(r.items.map((g) => g.status).toList(), ['good', 'bad', 'none']);
    });

    test('lista de strings sanea móvil y tracking', () {
      final r = UniversalImporter.parse(
        jsonEncode([
          'https://m.facebook.com/groups/12345/?mibextid=abc',
          'facebook.com/share/g/xyz999/?ref=share',
        ]),
      );
      expect(r.items.length, 2);
      expect(r.items[0].url, 'https://facebook.com/groups/12345/');
      expect(r.items[1].url, 'https://facebook.com/share/g/xyz999/');
    });

    test('objeto envoltura y anidado', () {
      final r1 = UniversalImporter.parse(
        jsonEncode({
          'grupos': [
            {'url': 'https://facebook.com/groups/a/'},
          ],
        }),
      );
      expect(r1.formato, 'json-objeto');
      expect(r1.items.length, 1);

      final r2 = UniversalImporter.parse(
        jsonEncode({
          'meta': {'version': 2, 'exportado': '2026-01-01'},
          'data': {
            'items': [
              {'link': 'https://facebook.com/groups/x/', 'estado': 'bueno'},
              {'href': 'https://facebook.com/groups/y/', 'rating': 'Medium'},
            ],
          },
        }),
      );
      expect(r2.items.length, 2);
      expect(r2.items[0].status, 'good');
      expect(r2.items[1].status, 'regular');
    });

    test('claves alternativas y estados en varios idiomas/emojis', () {
      final r = UniversalImporter.parse(
        jsonEncode([
          {'enlace': 'https://facebook.com/groups/a/', 'Calificación': 'MALO'},
          {'Link': 'https://facebook.com/groups/b/', 'state': '👍'},
          {'uri': 'https://facebook.com/groups/c/', 'quality': 'banned'},
          {'url': 'https://facebook.com/groups/d/', 'status': 'amarillo'},
          {'url': 'https://facebook.com/groups/e/', 'status': '???'},
        ]),
      );
      expect(r.items.map((g) => g.status).toList(), [
        'bad',
        'good',
        'bad',
        'regular',
        'none',
      ]);
    });

    test('mapa cuya clave es la URL', () {
      final r = UniversalImporter.parse(
        jsonEncode({
          'https://facebook.com/groups/a/': 'good',
          'https://facebook.com/groups/b/': {'status': 'bad'},
        }),
      );
      expect(r.items.length, 2);
      expect(r.items[0].status, 'good');
      expect(r.items[1].status, 'bad');
    });

    test('solo IDs de grupo', () {
      final r = UniversalImporter.parse(
        jsonEncode([
          {'group_id': 123456789, 'status': 'good'},
          {'id': 'ventas.madrid'},
        ]),
      );
      expect(r.items[0].url, 'https://facebook.com/groups/123456789/');
      expect(r.items[0].status, 'good');
      expect(r.items[1].url, 'https://facebook.com/groups/ventas.madrid/');
    });

    test('JSON Lines', () {
      const raw =
          '{"url":"https://facebook.com/groups/a/","status":"good"}\n'
          '{"url":"https://facebook.com/groups/b/"}\n';
      final r = UniversalImporter.parse(raw);
      expect(r.formato, 'jsonl');
      expect(r.items.length, 2);
      expect(r.items[0].status, 'good');
    });

    test('texto plano con enlaces mezclados con texto', () {
      const raw =
          'Mis grupos:\n'
          '- https://www.facebook.com/groups/aaa/?ref=x genial\n'
          'otro: m.facebook.com/groups/bbb\n'
          'nada que ver aquí\n';
      final r = UniversalImporter.parse(raw);
      expect(r.formato, 'texto/csv');
      expect(r.items.map((g) => g.url).toList(), [
        'https://facebook.com/groups/aaa/',
        'https://facebook.com/groups/bbb/',
      ]);
    });

    test('CSV con cabecera y estado', () {
      const raw =
          'url,estado,notas\n'
          'https://facebook.com/groups/a/,bueno,top\n'
          'https://facebook.com/groups/b/;mal\n'
          '12345678,medio\n';
      final r = UniversalImporter.parse(raw);
      expect(r.items.length, 3);
      expect(r.items.map((g) => g.status).toList(), ['good', 'bad', 'regular']);
      expect(r.items[2].url, 'https://facebook.com/groups/12345678/');
    });

    test('deduplicación interna adopta estado y cuenta inválidos', () {
      final r = UniversalImporter.parse(
        jsonEncode([
          {'url': 'https://facebook.com/groups/a/'},
          {'url': 'https://m.facebook.com/groups/a/?ref=1', 'status': 'good'},
          'https://facebook.com/photo/123',
        ]),
      );
      expect(r.items.length, 1);
      expect(r.items[0].status, 'good');
      expect(r.duplicadosEnArchivo, 1);
      expect(r.invalidos, 1);
      expect(r.detectados, 3);
    });

    test('entrada basura o vacía no lanza ni inventa grupos', () {
      expect(UniversalImporter.parse('').items, isEmpty);
      expect(UniversalImporter.parse('   ').formato, 'vacio');
      expect(UniversalImporter.parse('{{{ no es nada').items, isEmpty);
      expect(UniversalImporter.parse('42').items, isEmpty);
      expect(
        UniversalImporter.parse('[1, true, null, {"a": []}]').items,
        isEmpty,
      );
    });

    test('una palabra suelta no genera grupo', () {
      final r = UniversalImporter.parse(jsonEncode(['hola', 'good', 'abc']));
      expect(r.items, isEmpty);
    });

    test(
      'URL ajena en metadatos no contamina, pero sí en entradas de lista',
      () {
        final meta = UniversalImporter.parse(
          jsonEncode({
            'app': {'url': 'https://miapp.com/'},
            'grupos': [
              {'url': 'https://facebook.com/groups/a/'},
            ],
          }),
        );
        expect(meta.items.length, 1);
        expect(meta.items[0].url, 'https://facebook.com/groups/a/');
      },
    );

    test('BOM inicial se ignora', () {
      final r = UniversalImporter.parse(
        '\uFEFF[{"url":"https://facebook.com/groups/a/"}]',
      );
      expect(r.items.length, 1);
    });
  });

  group('normalizarEstado', () {
    test('casos básicos', () {
      expect(UniversalImporter.normalizarEstado('Bien'), 'good');
      expect(UniversalImporter.normalizarEstado(' REGULAR '), 'regular');
      expect(UniversalImporter.normalizarEstado('Mal'), 'bad');
      expect(UniversalImporter.normalizarEstado(null), 'none');
      expect(UniversalImporter.normalizarEstado(3), 'none');
      expect(UniversalImporter.normalizarEstado(''), 'none');
    });
  });

  group('FBUrlHelper nuevos', () {
    test('extraerEnlacesFB', () {
      final l = FBUrlHelper.extraerEnlacesFB(
        'mira https://facebook.com/groups/a/?x=1, y fb.me/g/b.',
      );
      expect(l.length, 2);
      expect(l[1], 'fb.me/g/b');
    });

    test('calcularFaltan y cuentaYPosicion con límites distintos de 25', () {
      expect(FBUrlHelper.calcularFaltan(0, 25), 25);
      expect(FBUrlHelper.calcularFaltan(12, 25), 13);
      expect(FBUrlHelper.calcularFaltan(25, 25), 0);
      expect(FBUrlHelper.calcularFaltan(51, 25), 24);
      expect(FBUrlHelper.calcularFaltan(10, 10), 0);
      expect(FBUrlHelper.calcularFaltan(13, 10), 7);
      expect(FBUrlHelper.cuentaYPosicion(53, 25), (cuenta: 3, posicion: 4));
      expect(FBUrlHelper.cuentaYPosicion(10, 10), (cuenta: 2, posicion: 1));
    });

    test('limpiarID de URL ajena usa host + ruta', () {
      expect(
        FBUrlHelper.limpiarID('https://www.ejemplo.com/a/b/?x=1'),
        'ejemplo.com/a/b',
      );
    });
  });
}
