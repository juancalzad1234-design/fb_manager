import 'package:flutter_test/flutter_test.dart';
import 'package:fb_manager/main.dart';

void main() {
  group('FB Manager Core Logic Tests', () {
    test('GroupItem JSON serialization & deserialization', () {
      final item = GroupItem(
        url: 'https://facebook.com/groups/ventas.madrid/',
        status: 'good',
      );
      final json = item.toJson();
      expect(json['url'], 'https://facebook.com/groups/ventas.madrid/');
      expect(json['status'], 'good');

      final fromJson = GroupItem.fromJson(json);
      expect(fromJson.url, item.url);
      expect(fromJson.status, 'good');

      // Test legacy string format
      final fromString = GroupItem.fromJson('https://facebook.com/groups/retro');
      expect(fromString.url, 'https://facebook.com/groups/retro');
      expect(fromString.status, 'none');

      // Test link field fallback
      final fromLink = GroupItem.fromJson({'link': 'https://facebook.com/groups/test'});
      expect(fromLink.url, 'https://facebook.com/groups/test');
    });

    test('Bloques de cuentas en grupos de 25', () {
      final List<GroupItem> grupos = List.generate(
        53,
        (i) => GroupItem(url: 'https://facebook.com/groups/group_$i'),
      );

      final total = grupos.length;
      final totalCuentas = (total + 24) ~/ 25;
      expect(totalCuentas, 3); // 25 + 25 + 3 = 53

      // Cuenta 1: 25 elementos
      final chunk1 = grupos.sublist(0, 25);
      expect(chunk1.length, 25);

      // Cuenta 2: 25 elementos
      final chunk2 = grupos.sublist(25, 50);
      expect(chunk2.length, 25);

      // Cuenta 3: 3 elementos restantes
      final chunk3 = grupos.sublist(50, 53);
      expect(chunk3.length, 3);
    });

    test('Lógica de faltantes en Radar de Misión', () {
      // Caso 1: 0 grupos
      int total = 0;
      int faltan = 25 - (total % 25);
      if (faltan == 25 && total > 0) faltan = 0;
      expect(faltan, 25);

      // Caso 2: 12 grupos
      total = 12;
      faltan = 25 - (total % 25);
      if (faltan == 25 && total > 0) faltan = 0;
      expect(faltan, 13);

      // Caso 3: 25 grupos exactos
      total = 25;
      faltan = 25 - (total % 25);
      if (faltan == 25 && total > 0) faltan = 0;
      expect(faltan, 0);

      // Caso 4: 50 grupos exactos
      total = 50;
      faltan = 25 - (total % 25);
      if (faltan == 25 && total > 0) faltan = 0;
      expect(faltan, 0);

      // Caso 5: 51 grupos
      total = 51;
      faltan = 25 - (total % 25);
      if (faltan == 25 && total > 0) faltan = 0;
      expect(faltan, 24);
    });

    test('Reemplazo automático de enlaces marcados como bad', () {
      final List<GroupItem> grupos = [
        GroupItem(url: 'https://facebook.com/groups/g1', status: 'good'),
        GroupItem(url: 'https://facebook.com/groups/g2', status: 'bad'),
        GroupItem(url: 'https://facebook.com/groups/g3', status: 'regular'),
      ];

      const nuevoUrl = 'https://facebook.com/groups/nuevo_grupo';
      final indexMalo = grupos.indexWhere((g) => g.status == 'bad');
      expect(indexMalo, 1);

      grupos[indexMalo] = GroupItem(url: nuevoUrl, status: 'none');

      expect(grupos.length, 3);
      expect(grupos[1].url, nuevoUrl);
      expect(grupos[1].status, 'none');
    });
  });
}
