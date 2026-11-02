import 'package:fb_manager/main.dart';
import 'package:flutter_test/flutter_test.dart';

GroupItem g(String id, [String status = 'none']) =>
    GroupItem(url: 'https://facebook.com/groups/$id/', status: status);

void main() {
  group('fusionarGrupos', () {
    test('añade nuevos al final y conserva el orden', () {
      final r = fusionarGrupos([g('a'), g('b')], [g('c'), g('d')]);
      expect(r.items.map((e) => e.url).toList(), [
        'https://facebook.com/groups/a/',
        'https://facebook.com/groups/b/',
        'https://facebook.com/groups/c/',
        'https://facebook.com/groups/d/',
      ]);
      expect(r.nuevos, 2);
      expect(r.repetidos, 0);
    });

    test('repetidos conservan el estado actual', () {
      final r = fusionarGrupos([g('a', 'good')], [g('a', 'bad')]);
      expect(r.items.length, 1);
      expect(r.items[0].status, 'good');
      expect(r.repetidos, 1);
      expect(r.estadosAdoptados, 0);
    });

    test('adopta estado entrante si el actual es none', () {
      final r = fusionarGrupos([g('a')], [g('a', 'regular')]);
      expect(r.items[0].status, 'regular');
      expect(r.estadosAdoptados, 1);
    });

    test('detecta el mismo ID en formatos de URL distintos', () {
      final r = fusionarGrupos(
        [g('12345')],
        [GroupItem(url: 'https://facebook.com/share/g/12345/')],
      );
      expect(r.items.length, 1);
      expect(r.repetidos, 1);
    });

    test('listas vacías', () {
      expect(fusionarGrupos([], []).items, isEmpty);
      expect(fusionarGrupos([g('a')], []).items.length, 1);
      expect(fusionarGrupos([], [g('a')]).nuevos, 1);
    });

    test('no muta las listas originales', () {
      final actual = [g('a')];
      final entrante = [g('a', 'good'), g('b')];
      fusionarGrupos(actual, entrante);
      expect(actual.length, 1);
      expect(actual[0].status, 'none');
      expect(entrante[0].status, 'good');
    });
  });
}
