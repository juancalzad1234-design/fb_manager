import '../models/group_item.dart';
import 'fb_url_helper.dart';

class MergeResult {
  final List<GroupItem> items;
  final int nuevos;
  final int repetidos;
  final int estadosAdoptados;

  const MergeResult({
    required this.items,
    required this.nuevos,
    required this.repetidos,
    required this.estadosAdoptados,
  });
}

/// Combina la lista [actual] con [entrante] sin duplicados (por ID de grupo).
///
/// - Los grupos nuevos se añaden al final.
/// - Si el grupo ya existe se conserva el de [actual]; solo se adopta la
///   calificación entrante cuando el existente está sin calificar ('none').
/// - No modifica las listas recibidas: trabaja sobre copias.
MergeResult fusionarGrupos(List<GroupItem> actual, List<GroupItem> entrante) {
  final resultado = actual.map((g) => g.copy()).toList();
  final porId = <String, GroupItem>{
    for (final g in resultado) FBUrlHelper.limpiarID(g.url): g,
  };

  int nuevos = 0;
  int repetidos = 0;
  int adoptados = 0;

  for (final inc in entrante) {
    final id = FBUrlHelper.limpiarID(inc.url);
    if (id.isEmpty) continue;
    final existente = porId[id];
    if (existente == null) {
      final copia = inc.copy();
      resultado.add(copia);
      porId[id] = copia;
      nuevos++;
    } else {
      repetidos++;
      if (existente.status == 'none' && inc.status != 'none') {
        existente.status = inc.status;
        adoptados++;
      }
    }
  }

  return MergeResult(
    items: resultado,
    nuevos: nuevos,
    repetidos: repetidos,
    estadosAdoptados: adoptados,
  );
}
