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

    test('Cálculo de cuenta y posición para reemplazo de grupos', () {
      int calcularCuenta(int idx) => (idx ~/ 25) + 1;
      int calcularPosicion(int idx) => (idx % 25) + 1;

      // Primer grupo de Cuenta 1
      expect(calcularCuenta(0), 1);
      expect(calcularPosicion(0), 1);

      // Último grupo de Cuenta 1
      expect(calcularCuenta(24), 1);
      expect(calcularPosicion(24), 25);

      // Primer grupo de Cuenta 2
      expect(calcularCuenta(25), 2);
      expect(calcularPosicion(25), 1);

      // Grupo en Cuenta 3 (índice 53 -> 25*2 + 3)
      expect(calcularCuenta(53), 3);
      expect(calcularPosicion(53), 4);
    });

    test('FBUrlHelper.sanearUrl elimina tracking y normaliza dominios', () {
      // Enlace móvil con tracking ?ref=share&mibextid=...
      final urlMovil = 'https://m.facebook.com/groups/12345/?ref=share&mibextid=wwXIfr';
      expect(FBUrlHelper.sanearUrl(urlMovil), 'https://facebook.com/groups/12345/');

      // Enlace de tipo share facebook.com/share/g/ID/
      final urlShare = 'https://www.facebook.com/share/g/9XyZ123/?mibextid=A7c9';
      expect(FBUrlHelper.sanearUrl(urlShare), 'https://facebook.com/share/g/9XyZ123/');

      // Enlace fb.me/g/ID
      final urlFbMe = 'https://fb.me/g/retrocomunidad?tracking=xyz';
      expect(FBUrlHelper.sanearUrl(urlFbMe), 'https://facebook.com/groups/retrocomunidad/');

      // Slug sin protocolo ni dominio
      final slug = 'ventas_madrid';
      expect(FBUrlHelper.sanearUrl(slug), 'https://facebook.com/groups/ventas_madrid/');

      // Enlace con caracteres invisibles / espacios
      final sucio = '\u200e https://facebook.com/groups/test_space/?rdid=123 \u200f';
      expect(FBUrlHelper.sanearUrl(sucio), 'https://facebook.com/groups/test_space/');
    });

    test('FBUrlHelper.limpiarID detecta duplicados entre diferentes formatos de URL', () {
      // Mismo ID en formato /groups/ y formato /share/g/
      final id1 = FBUrlHelper.limpiarID('https://facebook.com/groups/12345/');
      final id2 = FBUrlHelper.limpiarID('https://facebook.com/share/g/12345/?mibextid=abc');
      final id3 = FBUrlHelper.limpiarID('https://m.facebook.com/groups/12345?ref=share');
      final id4 = FBUrlHelper.limpiarID('https://fb.me/g/12345');

      expect(id1, '12345');
      expect(id2, '12345');
      expect(id3, '12345');
      expect(id4, '12345');
      expect(id1 == id2, isTrue);
      expect(id1 == id3, isTrue);
      expect(id1 == id4, isTrue);

      // Slug con nombre
      expect(FBUrlHelper.limpiarID('https://www.facebook.com/groups/ventas.madrid/'), 'ventas.madrid');
      expect(FBUrlHelper.limpiarID('ventas.madrid'), 'ventas.madrid');
    });

    test('FBUrlHelper.sanearGrupos sanea listas y detecta si hubo cambios', () {
      final listaSucia = [
        {'url': 'https://m.facebook.com/groups/12345/?mibextid=123', 'status': 'good'},
        {'url': 'https://facebook.com/groups/limpio/', 'status': 'regular'},
        'https://facebook.com/share/g/xyz999/?ref=share',
      ];

      final res = FBUrlHelper.sanearGrupos(listaSucia);
      expect(res.huboCambios, isTrue);
      expect(res.items.length, 3);
      expect(res.items[0].url, 'https://facebook.com/groups/12345/');
      expect(res.items[0].status, 'good');
      expect(res.items[1].url, 'https://facebook.com/groups/limpio/');
      expect(res.items[1].status, 'regular');
      expect(res.items[2].url, 'https://facebook.com/share/g/xyz999/');
      expect(res.items[2].status, 'none');

      // Lista ya saneada
      final listaLimpia = [
        GroupItem(url: 'https://facebook.com/groups/12345/', status: 'good'),
        GroupItem(url: 'https://facebook.com/groups/limpio/', status: 'regular'),
      ];
      final resLimpia = FBUrlHelper.sanearGrupos(listaLimpia);
      expect(resLimpia.huboCambios, isFalse);
    });
  });
}
