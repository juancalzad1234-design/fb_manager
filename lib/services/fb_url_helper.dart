import 'dart:math';

import '../models/group_item.dart';

// ==========================================
// URL SANITIZATION & PARSING HELPER
// ==========================================
class FBUrlHelper {
  /// Normaliza y sanea la URL eliminando espacios, caracteres ocultos y parámetros
  /// de rastreo (tracking: ?ref=..., ?mibextid=..., &rdid=..., etc.).
  /// Soporta enlaces directos, m.facebook.com, web.facebook.com,
  /// facebook.com/share/g/..., fb.me/g/... y fb.com.
  static String sanearUrl(String raw) {
    String clean = raw.replaceAll(RegExp(r'[\u200e\u200f\s]'), '');
    if (clean.isEmpty) return '';

    // Si no tiene esquema, determinar si es dominio o solo ID/path
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      if (RegExp(
        r'^(www\.|m\.|web\.)?(facebook\.com|fb\.com|fb\.me)',
        caseSensitive: false,
      ).hasMatch(clean)) {
        clean = 'https://$clean';
      } else if (clean.toLowerCase().startsWith('share/g/')) {
        clean = 'https://facebook.com/$clean';
      } else if (clean.toLowerCase().startsWith('groups/')) {
        clean = 'https://facebook.com/$clean';
      } else {
        clean = 'https://facebook.com/groups/${clean.replaceFirst(RegExp(r'^/+'), '')}';
      }
    }

    try {
      final uri = Uri.parse(clean);
      final host = uri.host.toLowerCase();
      final isFacebook = host.endsWith('facebook.com') ||
          host == 'fb.com' ||
          host == 'fb.me';

      if (isFacebook) {
        String path = uri.path;

        // Soporte para fb.me/g/ID -> /groups/ID
        if (host == 'fb.me' && path.toLowerCase().startsWith('/g/')) {
          path = '/groups/${path.substring(3)}';
        }

        // Unificar dobles barras
        path = path.replaceAll(RegExp(r'/+'), '/');

        // Asegurar barra final si no la tiene
        if (!path.endsWith('/')) {
          path = '$path/';
        }

        return 'https://facebook.com$path';
      } else {
        final cleanUri = Uri(
          scheme: uri.scheme.isNotEmpty ? uri.scheme : 'https',
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
        );
        return cleanUri.toString();
      }
    } catch (_) {
      final sinQuery = clean.split('?')[0].split('#')[0];
      return sinQuery.endsWith('/') ? sinQuery : '$sinQuery/';
    }
  }

  /// Extrae el ID o slug unificado del grupo para evitar duplicados.
  /// Identifica `/groups/<id>`, `/share/g/<id>`, `/g/<id>` y slugs directos.
  static String limpiarID(String url) {
    final clean = url.replaceAll(RegExp(r'[\u200e\u200f\s]'), '');
    final sinQuery = clean.split('?')[0].split('#')[0];

    // 0. URL de otro dominio: usar host + ruta como identificador
    final otro = RegExp(r'^https?://([^/]+)(/.*)?$', caseSensitive: false)
        .firstMatch(sinQuery);
    if (otro != null) {
      final host = otro.group(1)!.toLowerCase();
      if (!RegExp(r'(^|\.)(facebook\.com|fb\.com|fb\.me)$').hasMatch(host)) {
        return ('${host.replaceFirst('www.', '')}${otro.group(2) ?? ''}')
            .toLowerCase()
            .replaceAll(RegExp(r'/+$'), '');
      }
    }

    // 1. Regex para capturar el ID tras /groups/, /share/g/ o /g/
    final match = RegExp(
      r'(?:facebook\.com|fb\.com|fb\.me)?/(?:groups|share/g|g)/([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(sinQuery);

    if (match != null && match.group(1) != null) {
      return match.group(1)!.toLowerCase();
    }

    // 2. Fallback: remover prefijos comunes y tomar el primer segmento
    return sinQuery
        .replaceFirst(
          RegExp(
            r'^https?://(www\.|m\.|web\.)?(facebook\.com|fb\.com|fb\.me)/(groups/|share/g/|g/)?',
            caseSensitive: false,
          ),
          '',
        )
        .split('/')[0]
        .toLowerCase();
  }

  /// Sanea una lista de elementos (GroupItem, Map o String) asegurando que cada
  /// URL esté limpia de parámetros de tracking y normalizada.
  /// Retorna la lista resultante y un booleano indicando si hubo algún cambio.
  static ({List<GroupItem> items, bool huboCambios}) sanearGrupos(
    List<dynamic> rawList,
  ) {
    final List<GroupItem> lista = [];
    bool huboCambios = false;

    for (final item in rawList) {
      final GroupItem g = item is GroupItem ? item : GroupItem.fromJson(item);
      final original = g.url;
      if (original.isNotEmpty) {
        final saneada = sanearUrl(original);
        if (original != saneada) {
          huboCambios = true;
          g.url = saneada;
        }
      }
      lista.add(g);
    }

    return (items: lista, huboCambios: huboCambios);
  }

  /// Aleatoriza los grupos priorizando los activos:
  /// Separa los grupos en dos subconjuntos:
  /// - 'activos': grupos con estado distinto de 'bad' (ej. good, regular, none).
  /// - 'malos': grupos marcados explícitamente como 'bad'.
  /// Aplica shuffle únicamente al conjunto de grupos 'activos' para mezclarlos aleatoriamente.
  /// Concatena los grupos de modo que todos los 'activos' ocupen los primeros bloques
  /// (las primeras cuentas de 25) y todos los grupos 'malos' queden relegados al final de la lista global.
  static List<GroupItem> aleatorizarGrupos(
    List<GroupItem> grupos, [
    Random? random,
  ]) {
    final activos = grupos.where((g) => g.status != 'bad').toList();
    final malos = grupos.where((g) => g.status == 'bad').toList();

    activos.shuffle(random ?? Random());

    return [...activos, ...malos];
  }

  static final RegExp _enlaceFB = RegExp(
    r'(?:https?://)?(?:www\.|m\.|web\.|mbasic\.)?(?:facebook\.com|fb\.com|fb\.me)/[^\s,;"<>)\]]+',
    caseSensitive: false,
  );

  /// Devuelve todos los enlaces de Facebook encontrados en un texto libre,
  /// en orden de aparición y sin sanear.
  static List<String> extraerEnlacesFB(String texto) {
    return _enlaceFB
        .allMatches(texto)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[.\u2026]+$'), ''))
        .toList();
  }

  /// Cuántos grupos faltan para completar la cuenta actual.
  /// Devuelve 0 si el total es múltiplo exacto del límite (y hay grupos).
  static int calcularFaltan(int total, int limite) {
    int faltan = limite - (total % limite);
    if (faltan == limite && total > 0) faltan = 0;
    return faltan;
  }

  /// Número de cuenta y posición dentro de ella (ambos base 1) para un índice global.
  static ({int cuenta, int posicion}) cuentaYPosicion(int idx, int limite) {
    return (cuenta: (idx ~/ limite) + 1, posicion: (idx % limite) + 1);
  }
}
