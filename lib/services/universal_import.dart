import 'dart:convert';

import '../models/group_item.dart';
import 'fb_url_helper.dart';

/// Resultado de leer un contenido arbitrario y adaptarlo al formato de la app.
class ImportResult {
  /// Grupos ya saneados y sin duplicados internos.
  final List<GroupItem> items;

  /// 'json-lista', 'json-objeto', 'jsonl', 'texto/csv' o 'vacio'.
  final String formato;

  /// Candidatos encontrados antes de filtrar inválidos y duplicados.
  final int detectados;

  /// Candidatos repetidos dentro del propio contenido.
  final int duplicadosEnArchivo;

  /// Candidatos descartados por no ser un grupo identificable.
  final int invalidos;

  const ImportResult({
    required this.items,
    required this.formato,
    required this.detectados,
    required this.duplicadosEnArchivo,
    required this.invalidos,
  });
}

/// Lector universal: acepta cualquier JSON (listas, objetos anidados, claves
/// alternativas, estados en otros idiomas), JSON Lines, texto plano con
/// enlaces y CSV, y lo convierte a una lista de [GroupItem].
class UniversalImporter {
  static const int _maxProfundidad = 12;

  static const Set<String> _clavesUrl = {
    'url',
    'link',
    'href',
    'uri',
    'enlace',
    'permalink',
    'groupurl',
    'grouplink',
    'grupo',
    'web',
  };

  static const Set<String> _clavesEstado = {
    'status',
    'estado',
    'rating',
    'rate',
    'calificacion',
    'calidad',
    'quality',
    'state',
    'resultado',
    'valoracion',
  };

  static const Set<String> _clavesId = {'id', 'groupid', 'gid'};

  static const Map<String, String> _estados = {
    // good
    'good': 'good',
    'bien': 'good',
    'bueno': 'good',
    'buena': 'good',
    'ok': 'good',
    'excelente': 'good',
    'positivo': 'good',
    'positive': 'good',
    'verde': 'good',
    'green': 'good',
    '👍': 'good',
    '✅': 'good',
    '🟢': 'good',
    '+': 'good',
    // regular
    'regular': 'regular',
    'medio': 'regular',
    'media': 'regular',
    'medium': 'regular',
    'mid': 'regular',
    'neutral': 'regular',
    'normal': 'regular',
    'amarillo': 'regular',
    'yellow': 'regular',
    '🟡': 'regular',
    // bad
    'bad': 'bad',
    'mal': 'bad',
    'malo': 'bad',
    'mala': 'bad',
    'baneado': 'bad',
    'banned': 'bad',
    'eliminado': 'bad',
    'removed': 'bad',
    'muerto': 'bad',
    'dead': 'bad',
    'rojo': 'bad',
    'red': 'bad',
    'negativo': 'bad',
    'negative': 'bad',
    '👎': 'bad',
    '❌': 'bad',
    '🔴': 'bad',
    '-': 'bad',
    '−': 'bad',
  };

  static final RegExp _enlaceGrupo = RegExp(
    r'/(?:groups|share/g|g)/[^/?#\s]+',
    caseSensitive: false,
  );
  static final RegExp _idNumerico = RegExp(r'^\d{5,}$');
  static final RegExp _rutaGrupo = RegExp(
    r'^(?:groups|share/g|g)/[^\s/]+/?$',
    caseSensitive: false,
  );
  static const Set<String> _idsInvalidos = {
    '',
    'groups',
    'g',
    'share',
    'http:',
    'https:',
  };

  // ----------------------------------------------------
  // API pública
  // ----------------------------------------------------
  static ImportResult parse(String raw) {
    final texto = raw.replaceAll('\uFEFF', '').trim();
    final ctx = _Contexto();

    if (texto.isEmpty) {
      return ctx.resultado('vacio');
    }

    String formato;
    final decoded = _tryDecode(texto);
    if (decoded is List) {
      formato = 'json-lista';
      _recorrer(decoded, ctx, 0, false);
    } else if (decoded is Map) {
      formato = 'json-objeto';
      _recorrer(decoded, ctx, 0, false);
    } else {
      final jsonl = _tryJsonLines(texto);
      if (jsonl != null) {
        formato = 'jsonl';
        for (final nodo in jsonl) {
          _recorrer(nodo, ctx, 0, false);
        }
      } else {
        formato = 'texto/csv';
        _procesarTexto(texto, ctx);
      }
    }
    return ctx.resultado(formato);
  }

  /// Convierte un valor libre ('Bueno', '👍', 'MAL'...) a good/regular/bad/none.
  static String normalizarEstado(dynamic valor) {
    if (valor == null || valor is bool || valor is num) return 'none';
    final t = _quitarAcentos(valor.toString().trim().toLowerCase());
    if (t.isEmpty) return 'none';
    final directo = _estados[t];
    if (directo != null) return directo;
    final soloLetras = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _estados[soloLetras] ?? 'none';
  }

  // ----------------------------------------------------
  // JSON
  // ----------------------------------------------------
  static dynamic _tryDecode(String texto) {
    try {
      return jsonDecode(texto);
    } catch (_) {
      return null;
    }
  }

  static List<dynamic>? _tryJsonLines(String texto) {
    final lineas = texto
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lineas.length < 2) return null;
    final nodos = <dynamic>[];
    for (final l in lineas) {
      try {
        nodos.add(jsonDecode(l));
      } catch (_) {
        return null;
      }
    }
    return nodos;
  }

  static void _recorrer(dynamic nodo, _Contexto ctx, int profundidad, bool enLista) {
    if (profundidad > _maxProfundidad) return;

    if (nodo is List) {
      for (final e in nodo) {
        _recorrer(e, ctx, profundidad + 1, true);
      }
      return;
    }

    if (nodo is String) {
      _procesarCadenaSuelta(nodo, ctx);
      return;
    }

    if (nodo is! Map) return;

    String? url;
    dynamic estadoRaw;
    bool tieneEstado = false;
    String? id;

    for (final e in nodo.entries) {
      final k = _normKey(e.key.toString());
      final v = e.value;
      if (url == null && _clavesUrl.contains(k) && v is String && v.trim().isNotEmpty) {
        url = v;
      }
      if (!tieneEstado && _clavesEstado.contains(k)) {
        tieneEstado = true;
        estadoRaw = v;
      }
      if (id == null && _clavesId.contains(k) && (v is num || v is String)) {
        final s = v.toString().trim();
        if (RegExp(r'^[\w.\-]+$').hasMatch(s) && s.length >= 3) id = s;
      }
    }

    if (url != null) {
      final esFb = FBUrlHelper.extraerEnlacesFB(url).isNotEmpty ||
          _rutaGrupo.hasMatch(url.trim()) ||
          _idNumerico.hasMatch(url.trim());
      // Las URL ajenas a Facebook solo se aceptan si parecen una entrada de
      // lista (elemento de una lista o con campo de estado).
      if (esFb || enLista || tieneEstado) {
        ctx.agregarUrl(url, normalizarEstado(estadoRaw));
        return;
      }
    }

    if (id != null) {
      ctx.agregarUrl('https://facebook.com/groups/$id', normalizarEstado(estadoRaw));
      return;
    }

    for (final e in nodo.entries) {
      final clave = e.key.toString();
      final v = e.value;
      if (_pareceClaveEnlace(clave)) {
        final estado = v is Map ? _estadoDeMapa(v) : normalizarEstado(v);
        ctx.agregarUrl(clave, estado);
      } else {
        _recorrer(v, ctx, profundidad + 1, false);
      }
    }
  }

  static String _estadoDeMapa(Map m) {
    for (final e in m.entries) {
      if (_clavesEstado.contains(_normKey(e.key.toString()))) {
        return normalizarEstado(e.value);
      }
    }
    return 'none';
  }

  static bool _pareceClaveEnlace(String clave) {
    final c = clave.trim();
    return _rutaGrupo.hasMatch(c) ||
        (FBUrlHelper.extraerEnlacesFB(c).isNotEmpty && _enlaceGrupo.hasMatch(c));
  }

  static void _procesarCadenaSuelta(String s, _Contexto ctx, {String estado = 'none'}) {
    final enlaces = FBUrlHelper.extraerEnlacesFB(s);
    if (enlaces.isNotEmpty) {
      for (final e in enlaces) {
        if (_enlaceGrupo.hasMatch(e)) {
          ctx.agregarUrl(e, estado);
        } else {
          ctx.detectados++;
          ctx.invalidos++;
        }
      }
      return;
    }
    final t = s.trim();
    if (_idNumerico.hasMatch(t) || _rutaGrupo.hasMatch(t)) {
      ctx.agregarUrl(t, estado);
    }
    // Cualquier otra palabra suelta se ignora para no inventar grupos.
  }

  // ----------------------------------------------------
  // Texto plano / CSV
  // ----------------------------------------------------
  static void _procesarTexto(String texto, _Contexto ctx) {
    for (final linea in texto.split(RegExp(r'\r?\n'))) {
      final l = linea.trim();
      if (l.isEmpty) continue;

      final campos = l.split(RegExp(r'[,;\t|]')).map((c) => c.trim()).toList();
      String estado = 'none';
      for (final c in campos) {
        if (FBUrlHelper.extraerEnlacesFB(c).isNotEmpty) continue;
        final e = normalizarEstado(c);
        if (e != 'none') {
          estado = e;
          break;
        }
      }

      final enlaces = FBUrlHelper.extraerEnlacesFB(l);
      if (enlaces.isNotEmpty) {
        _procesarCadenaSuelta(l, ctx, estado: estado);
        continue;
      }
      for (final c in campos) {
        if (_idNumerico.hasMatch(c) || _rutaGrupo.hasMatch(c)) {
          ctx.agregarUrl(c, estado);
        }
      }
    }
  }

  // ----------------------------------------------------
  // Utilidades
  // ----------------------------------------------------
  static String _quitarAcentos(String s) {
    const mapa = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    };
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      sb.write(mapa[ch] ?? ch);
    }
    return sb.toString();
  }

  static String _normKey(String k) =>
      _quitarAcentos(k.toLowerCase()).replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _Contexto {
  final Map<String, GroupItem> porId = {};
  int detectados = 0;
  int duplicados = 0;
  int invalidos = 0;

  void agregarUrl(String raw, String estado) {
    detectados++;
    final url = FBUrlHelper.sanearUrl(raw);
    final id = FBUrlHelper.limpiarID(url);
    if (url.isEmpty || UniversalImporter._idsInvalidos.contains(id)) {
      invalidos++;
      return;
    }
    final existente = porId[id];
    if (existente != null) {
      duplicados++;
      if (existente.status == 'none' && estado != 'none') {
        existente.status = estado;
      }
      return;
    }
    porId[id] = GroupItem(url: url, status: estado);
  }

  ImportResult resultado(String formato) => ImportResult(
        items: porId.values.toList(),
        formato: formato,
        detectados: detectados,
        duplicadosEnArchivo: duplicados,
        invalidos: invalidos,
      );
}
