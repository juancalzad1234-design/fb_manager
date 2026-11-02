import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/group_item.dart';
import 'services/fb_url_helper.dart';
import 'services/merge_groups.dart';
import 'services/universal_import.dart';

export 'models/group_item.dart';
export 'services/fb_url_helper.dart';
export 'services/merge_groups.dart';
export 'services/universal_import.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const CyberFBManagerApp());
}

// ==========================================
// COLOR PALETTE & RETRO CONSTANTS
// ==========================================
class CyberTheme {
  static const Color bg = Color(0xFF000000);
  static const Color surface = Color(0xFF111111);
  static const Color surfaceVariant = Color(0xFF222222);
  static const Color primary = Color(0xFF5A99FF);
  static const Color secondary = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFEB3B);
  static const Color error = Color(0xFFFF5252);
  static const Color text = Color(0xFFEEEEEE);
  static const Color textMuted = Color(0xFF888888);
  static const Color border = Color(0xFF444444);
  static const Color trackerBg = Color(0xFF001100);
  static const Color currentBg = Color(0xFF001133);
  static const Color greenActiveBg = Color(0xFF003300);
  static const Color yellowActiveBg = Color(0xFF333300);
  static const Color redActiveBg = Color(0xFF330000);

  static TextStyle mono({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.normal,
    Color color = text,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      decoration: decoration,
      decorationColor: color,
    );
  }
}

// ==========================================
// ROOT APP
// ==========================================
class CyberFBManagerApp extends StatelessWidget {
  const CyberFBManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyber FB Manager Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: CyberTheme.bg,
        primaryColor: CyberTheme.primary,
        fontFamily: 'monospace',
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: CyberTheme.primary,
          selectionColor: Color(0x665A99FF),
          selectionHandleColor: CyberTheme.primary,
        ),
      ),
      home: const FBManagerScreen(),
    );
  }
}

// ==========================================
// MAIN SCREEN
// ==========================================
class FBManagerScreen extends StatefulWidget {
  const FBManagerScreen({super.key});

  @override
  State<FBManagerScreen> createState() => _FBManagerScreenState();
}

/// Copia del estado previo a una acción destructiva, para poder deshacerla.
class _UndoSnapshot {
  final List<GroupItem> grupos;
  final String actual;
  final int? mision;

  _UndoSnapshot({required this.grupos, required this.actual, this.mision});
}

enum _Insercion { agregado, reemplazo, invalido, repetido }

class _ResultadoInsercion {
  final _Insercion tipo;
  final int cuenta;
  final int posicion;
  final String urlAnterior;

  const _ResultadoInsercion(
    this.tipo, {
    this.cuenta = 0,
    this.posicion = 0,
    this.urlAnterior = '',
  });
}

class _FBManagerScreenState extends State<FBManagerScreen> {
  static const String _prefsGroupsPerAccountKey = 'groups_per_account';
  static const String _prefsListKey = 'cyber_fb_list';
  static const String _prefsBackupKey = 'cyber_fb_list_backup';
  static const String _prefsCurrentKey = 'cyber_fb_current_url';
  static const String _prefsMissionKey = 'cyber_fb_mission_count';
  static const String _prefsAutoAdvanceKey = 'cyber_fb_auto_advance';
  static const int _defaultGroupsPerAccount = 25;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<GroupItem> _grupos = [];
  String _urlActual = '';
  int _agregadosSesion = 0;
  int _groupsPerAccount = _defaultGroupsPerAccount;
  bool _misionCompletada = false;
  Timer? _celebracionTimer;

  bool _autoAvanzar = false;
  String _filtroEstado = 'all'; // all, none, good, regular, bad
  String _busqueda = '';

  _UndoSnapshot? _undo;
  int _undoToken = 0;

  Future<void> _guardando = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _celebracionTimer?.cancel();
    _urlController.dispose();
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ----------------------------------------------------
  // VIBRATION & FEEDBACK
  // ----------------------------------------------------
  void _vibrar({int durationMs = 25}) {
    if (durationMs >= 50) {
      HapticFeedback.heavyImpact();
    } else if (durationMs >= 30) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _reproducirSonidoVictoria() async {
    try {
      _vibrar(durationMs: 60);
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/victory_8bit.wav'));
    } catch (e) {
      debugPrint('Error reproduciendo audio: $e');
    }
  }

  // ----------------------------------------------------
  // PERSISTENCE
  // ----------------------------------------------------
  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString(_prefsListKey);
    final curr = prefs.getString(_prefsCurrentKey) ?? '';
    final savedLimit = prefs.getInt(_prefsGroupsPerAccountKey);
    final validLimit = (savedLimit != null && savedLimit >= 1)
        ? savedLimit
        : _defaultGroupsPerAccount;
    final savedMission = prefs.getInt(_prefsMissionKey) ?? 0;
    final validMission = (savedMission >= 0 && savedMission < validLimit)
        ? savedMission
        : 0;
    final auto = prefs.getBool(_prefsAutoAdvanceKey) ?? false;

    List<GroupItem> parsed = [];
    bool seModificaronUrls = false;

    if (rawList != null && rawList.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawList);
        if (decoded is List) {
          final resultado = FBUrlHelper.sanearGrupos(decoded);
          parsed = resultado.items;
          if (resultado.huboCambios) {
            seModificaronUrls = true;
          }
        }
      } catch (e) {
        debugPrint('Error parseando storage: $e');
      }
    }

    final currSaneada = curr.isNotEmpty ? FBUrlHelper.sanearUrl(curr) : '';
    if (curr.isNotEmpty && curr != currSaneada) {
      seModificaronUrls = true;
    }

    if (mounted) {
      setState(() {
        _grupos = parsed;
        _urlActual = currSaneada;
        _groupsPerAccount = validLimit;
        _agregadosSesion = validMission;
        _autoAvanzar = auto;
      });
    } else {
      _grupos = parsed;
      _urlActual = currSaneada;
      _groupsPerAccount = validLimit;
      _agregadosSesion = validMission;
      _autoAvanzar = auto;
    }

    if (savedLimit == null || savedLimit < 1) {
      await prefs.setInt(_prefsGroupsPerAccountKey, validLimit);
    }

    if (seModificaronUrls) {
      final encoded = jsonEncode(parsed.map((g) => g.toJson()).toList());
      await prefs.setString(_prefsListKey, encoded);
      await prefs.setString(_prefsCurrentKey, currSaneada);
    }
  }

  /// Guarda el estado actual. Las escrituras se encolan para que se apliquen
  /// siempre en el orden en que se pidieron.
  Future<void> _guardarDatos() {
    final encoded = jsonEncode(_grupos.map((g) => g.toJson()).toList());
    final actual = _urlActual;
    final limite = _groupsPerAccount;
    final mision = _agregadosSesion;
    final auto = _autoAvanzar;

    _guardando = _guardando.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsListKey, encoded);
        await prefs.setString(_prefsCurrentKey, actual);
        await prefs.setInt(_prefsGroupsPerAccountKey, limite);
        await prefs.setInt(_prefsMissionKey, mision);
        await prefs.setBool(_prefsAutoAdvanceKey, auto);
      } catch (e) {
        debugPrint('Error guardando datos: $e');
        if (mounted) _mostrarMensaje('ERROR AL GUARDAR', isError: true);
      }
    });
    return _guardando;
  }

  /// Copia de seguridad automática de la lista previa a una importación.
  Future<void> _guardarBackup(List<GroupItem> previa) {
    final encoded = jsonEncode(previa.map((g) => g.toJson()).toList());
    _guardando = _guardando.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsBackupKey, encoded);
      } catch (e) {
        debugPrint('Error guardando backup: $e');
      }
    });
    return _guardando;
  }

  Future<void> _actualizarGruposPorCuenta(
    int nuevoLimite, {
    String? mensaje,
  }) async {
    if (nuevoLimite < 1) return;
    _vibrar(durationMs: 25);
    setState(() {
      _groupsPerAccount = nuevoLimite;
      if (_agregadosSesion >= nuevoLimite) _agregadosSesion = 0;
    });
    await _guardarDatos();
    _mostrarMensaje(
      mensaje ?? 'LÍMITE: $_groupsPerAccount GRUPOS/CUENTA',
      isError: false,
    );
  }

  // ----------------------------------------------------
  // NOTIFICATIONS / UNDO
  // ----------------------------------------------------
  /// Muestra un mensaje flotante visible desde cualquier posición del scroll.
  void _mostrarMensaje(
    String texto, {
    required bool isError,
    bool deshacer = false,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final color = isError ? CyberTheme.error : CyberTheme.secondary;
    final token = ++_undoToken;

    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CyberTheme.surface,
        shape: Border.all(color: color, width: 2),
        duration: Duration(seconds: deshacer ? 6 : 3),
        action: deshacer
            ? SnackBarAction(
                label: 'DESHACER',
                textColor: CyberTheme.warning,
                onPressed: _deshacer,
              )
            : null,
        content: Text(
          texto,
          style: CyberTheme.mono(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );

    if (deshacer) {
      controller.closed.then((reason) {
        if (reason != SnackBarClosedReason.action && token == _undoToken) {
          _undo = null;
        }
      });
    } else {
      _undo = null;
    }
  }

  void _guardarSnapshot({bool conMision = false}) {
    _undo = _UndoSnapshot(
      grupos: _grupos.map((g) => g.copy()).toList(),
      actual: _urlActual,
      mision: conMision ? _agregadosSesion : null,
    );
  }

  void _deshacer() {
    final u = _undo;
    if (u == null) return;
    _undo = null;
    _vibrar(durationMs: 25);
    setState(() {
      _grupos = u.grupos;
      _urlActual = u.actual;
      if (u.mision != null) _agregadosSesion = u.mision!;
    });
    _guardarDatos();
    _mostrarMensaje('ACCIÓN DESHECHA', isError: false);
  }

  // ----------------------------------------------------
  // BUSINESS LOGIC
  // ----------------------------------------------------
  bool _esActual(GroupItem g) {
    if (_urlActual.isEmpty || g.url.isEmpty) return false;
    return FBUrlHelper.limpiarID(g.url) == FBUrlHelper.limpiarID(_urlActual);
  }

  bool _existeDuplicado(String url, {int? ignorarIndex}) {
    final id = FBUrlHelper.limpiarID(url);
    for (var i = 0; i < _grupos.length; i++) {
      if (i == ignorarIndex) continue;
      if (FBUrlHelper.limpiarID(_grupos[i].url) == id) return true;
    }
    return false;
  }

  List<int> _calcularVisibles() {
    final q = _busqueda.trim().toLowerCase();
    final out = <int>[];
    for (var i = 0; i < _grupos.length; i++) {
      final g = _grupos[i];
      if (_filtroEstado != 'all' && g.status != _filtroEstado) continue;
      if (q.isNotEmpty && !g.url.toLowerCase().contains(q)) continue;
      out.add(i);
    }
    return out;
  }

  List<int> _conteoEstados(int start, int end) {
    int good = 0, regular = 0, bad = 0, none = 0;
    for (var i = start; i < end && i < _grupos.length; i++) {
      switch (_grupos[i].status) {
        case 'good':
          good++;
        case 'regular':
          regular++;
        case 'bad':
          bad++;
        default:
          none++;
      }
    }
    return [good, regular, bad, none];
  }

  /// Inserta un grupo: reemplaza el primero marcado 'bad' o lo añade al final.
  /// No muestra mensajes ni guarda: lo hace quien llama.
  _ResultadoInsercion _insertarGrupo(String raw, {String status = 'none'}) {
    final sanitized = FBUrlHelper.sanearUrl(raw.trim());
    final id = FBUrlHelper.limpiarID(sanitized);
    if (id.isEmpty) return const _ResultadoInsercion(_Insercion.invalido);
    if (_existeDuplicado(sanitized)) {
      return const _ResultadoInsercion(_Insercion.repetido);
    }

    final indexMalo = _grupos.indexWhere((g) => g.status == 'bad');
    if (indexMalo != -1) {
      final pos = FBUrlHelper.cuentaYPosicion(indexMalo, _groupsPerAccount);
      final anterior = _grupos[indexMalo].url;
      if (_esActual(_grupos[indexMalo])) _urlActual = sanitized;
      _grupos[indexMalo] = GroupItem(url: sanitized, status: status);
      return _ResultadoInsercion(
        _Insercion.reemplazo,
        cuenta: pos.cuenta,
        posicion: pos.posicion,
        urlAnterior: anterior,
      );
    }

    _grupos.add(GroupItem(url: sanitized, status: status));
    return const _ResultadoInsercion(_Insercion.agregado);
  }

  /// Suma al contador de misión. Al llegar a la meta lo reinicia a 0 (ya
  /// persistido) y muestra la celebración unos segundos.
  void _sumarMision(int n) {
    if (n <= 0) return;
    _agregadosSesion += n;
    if (_agregadosSesion >= _groupsPerAccount) {
      _agregadosSesion = _agregadosSesion % _groupsPerAccount;
      _reproducirSonidoVictoria();
      _misionCompletada = true;
      _celebracionTimer?.cancel();
      _celebracionTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _misionCompletada = false);
      });
    }
  }

  void _agregarGrupo() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;

    final esMultiple =
        raw.contains('\n') ||
        raw.startsWith('[') ||
        raw.startsWith('{') ||
        FBUrlHelper.extraerEnlacesFB(raw).length > 1;

    if (esMultiple) {
      _agregarVarios(raw);
      return;
    }

    final sanitized = FBUrlHelper.sanearUrl(raw);
    final tienePosibleReemplazo = _grupos.any((g) => g.status == 'bad');
    final idNuevo = FBUrlHelper.limpiarID(sanitized);
    if (idNuevo.isNotEmpty &&
        tienePosibleReemplazo &&
        !_existeDuplicado(sanitized)) {
      _guardarSnapshot(conMision: true);
    }

    final res = _insertarGrupo(raw);
    switch (res.tipo) {
      case _Insercion.invalido:
        _vibrar(durationMs: 50);
        _mostrarMensaje('ENLACE NO VÁLIDO', isError: true);
        return;
      case _Insercion.repetido:
        _vibrar(durationMs: 60);
        _mostrarMensaje('GRUPO REPETIDO', isError: true);
        return;
      case _Insercion.reemplazo:
        _vibrar(durationMs: 25);
        _sumarMision(1);
        _mostrarMensaje(
          'REEMPLAZADO EN CUENTA ${res.cuenta} (#${res.posicion})\nANTERIOR: ${res.urlAnterior}',
          isError: false,
          deshacer: true,
        );
      case _Insercion.agregado:
        _vibrar(durationMs: 25);
        _sumarMision(1);
        _mostrarMensaje('AÑADIDO', isError: false);
    }

    _urlController.clear();
    _guardarDatos();
    setState(() {});
  }

  void _agregarVarios(String raw) {
    final lectura = UniversalImporter.parse(raw);
    if (lectura.items.isEmpty) {
      _vibrar(durationMs: 50);
      _mostrarMensaje('ENLACE NO VÁLIDO', isError: true);
      return;
    }

    _guardarSnapshot(conMision: true);
    int agregados = 0;
    int repetidos = lectura.duplicadosEnArchivo;
    for (final item in lectura.items) {
      final res = _insertarGrupo(item.url, status: item.status);
      if (res.tipo == _Insercion.repetido) {
        repetidos++;
      } else if (res.tipo != _Insercion.invalido) {
        agregados++;
      }
    }

    if (agregados == 0) {
      _undo = null;
      _vibrar(durationMs: 60);
      _mostrarMensaje('AÑADIDOS: 0 · REPETIDOS: $repetidos', isError: true);
      return;
    }

    _vibrar(durationMs: 25);
    _sumarMision(agregados);
    _mostrarMensaje(
      'AÑADIDOS: $agregados · REPETIDOS: $repetidos',
      isError: false,
      deshacer: true,
    );
    _urlController.clear();
    _guardarDatos();
    setState(() {});
  }

  Future<void> _pegarDelPortapapeles() async {
    _vibrar(durationMs: 20);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = data?.text?.trim() ?? '';
    if (texto.isEmpty) {
      _mostrarMensaje('PORTAPAPELES VACÍO', isError: true);
      return;
    }
    setState(() {
      _urlController.text = texto;
      _urlController.selection = TextSelection.collapsed(offset: texto.length);
    });
  }

  void _marcarActual(String url) {
    _vibrar(durationMs: 20);
    setState(() {
      _urlActual = url;
    });
    _guardarDatos();
  }

  /// Desplaza la lista hasta el grupo con índice global [globalIdx].
  /// Devuelve false si el grupo no es visible con el filtro actual.
  bool _scrollAGlobal(int globalIdx, {String? mensajeExito}) {
    final visibles = _calcularVisibles();
    final pos = visibles.indexOf(globalIdx);
    if (pos == -1) return false;
    final targetIndex = pos + 1; // El índice 0 es el panel de control superior

    void hacerScroll() {
      _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.15,
      );
      if (mensajeExito != null) {
        _mostrarMensaje(mensajeExito, isError: false);
      }
    }

    if (_itemScrollController.isAttached) {
      hacerScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) hacerScroll();
      });
    }
    return true;
  }

  void _irAlActual() {
    _vibrar(durationMs: 35);
    if (_urlActual.isEmpty) {
      _mostrarMensaje('SIN GRUPO ACTUAL', isError: true);
      return;
    }

    final index = _grupos.indexWhere(_esActual);
    if (index == -1) {
      _mostrarMensaje('NO ENCONTRADO EN LA LISTA', isError: true);
      return;
    }

    final ok = _scrollAGlobal(index, mensajeExito: 'ENFOCANDO...');
    if (!ok) {
      _mostrarMensaje('ACTUAL OCULTO POR EL FILTRO', isError: true);
    }
  }

  int _siguienteSinCalificar(int desde) {
    final n = _grupos.length;
    for (var k = 1; k <= n; k++) {
      final i = (desde + k) % n;
      if (_grupos[i].status == 'none' && !(i == desde && desde >= 0)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _abrirSiguienteSinCalificar() async {
    _vibrar(durationMs: 30);
    if (_grupos.isEmpty) {
      _mostrarMensaje('AÚN NO HAY GRUPOS EN LA LISTA', isError: true);
      return;
    }
    final desde = _grupos.indexWhere(_esActual);
    final next = _siguienteSinCalificar(desde);
    if (next == -1) {
      _mostrarMensaje('NO HAY GRUPOS SIN CALIFICAR', isError: true);
      return;
    }
    final visible = _scrollAGlobal(next);
    if (!visible) {
      _mostrarMensaje('SIGUIENTE FUERA DEL FILTRO ACTUAL', isError: false);
    }
    await _abrirEnFB(_grupos[next].url);
  }

  Future<void> _abrirEnFB(String url) async {
    if (url.isEmpty || url == 'undefined') {
      _mostrarMensaje('ENLACE DAÑADO', isError: true);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _mostrarMensaje('ENLACE DAÑADO', isError: true);
      return;
    }

    _vibrar(durationMs: 30);
    bool abierto = false;
    try {
      abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      abierto = false;
    }
    if (!abierto) {
      try {
        abierto = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        abierto = false;
      }
    }

    if (!mounted) return;
    if (abierto) {
      _marcarActual(url);
    } else {
      _mostrarMensaje('NO SE PUDO ABRIR ENLACE', isError: true);
    }
  }

  void _toggleCalificacion(int globalIndex, String estado) {
    _vibrar(
      durationMs: estado == 'good' ? 15 : (estado == 'regular' ? 20 : 40),
    );
    final eraActual = _esActual(_grupos[globalIndex]);
    bool calificado = false;
    setState(() {
      if (_grupos[globalIndex].status == estado) {
        _grupos[globalIndex].status = 'none';
      } else {
        _grupos[globalIndex].status = estado;
        calificado = true;
      }
    });

    if (_autoAvanzar && eraActual && calificado) {
      final next = _siguienteSinCalificar(globalIndex);
      if (next != -1) {
        setState(() {
          _urlActual = _grupos[next].url;
        });
        _scrollAGlobal(next);
      }
    }
    _guardarDatos();
  }

  void _toggleAutoAvanzar() {
    _vibrar(durationMs: 15);
    setState(() {
      _autoAvanzar = !_autoAvanzar;
    });
    _guardarDatos();
    _mostrarMensaje(
      _autoAvanzar
          ? 'AVANZAR AL CALIFICAR: ACTIVADO'
          : 'AVANZAR AL CALIFICAR: DESACTIVADO',
      isError: false,
    );
  }

  void _copiarEnlace(String url) {
    Clipboard.setData(ClipboardData(text: url));
    _vibrar(durationMs: 20);
    _mostrarMensaje('ENLACE COPIADO', isError: false);
  }

  void _confirmarAleatorizarGrupos() {
    _vibrar(durationMs: 25);
    if (_grupos.length <= 1) {
      _mostrarMensaje('SE NECESITAN AL MENOS 2 GRUPOS', isError: true);
      return;
    }

    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return CyberDialog(
          title: 'ALEATORIZAR GRUPOS',
          color: CyberTheme.warning,
          titleSize: 18,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Esta acción reorganizará todos los enlaces al azar y cambiará el orden de las cuentas de $_groupsPerAccount.\n\n¿Deseas continuar?',
              style: CyberTheme.mono(fontSize: 13, color: CyberTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RetroButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.of(ctx).pop(),
                  backgroundColor: CyberTheme.surfaceVariant,
                  textColor: CyberTheme.text,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                const SizedBox(width: 14),
                RetroButton(
                  label: 'Aleatorizar',
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _aleatorizarGrupos();
                  },
                  backgroundColor: CyberTheme.warning,
                  textColor: Colors.black,
                  borderColor: CyberTheme.warning,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _aleatorizarGrupos() {
    _vibrar(durationMs: 40);
    if (_grupos.length <= 1) return;
    _guardarSnapshot();
    setState(() {
      _grupos = FBUrlHelper.aleatorizarGrupos(_grupos);
    });
    _guardarDatos();
    _mostrarMensaje('GRUPOS ALEATORIZADOS', isError: false, deshacer: true);
  }

  void _confirmarReiniciarMision() {
    _vibrar(durationMs: 20);
    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return CyberDialog(
          title: 'REINICIAR CONTADOR',
          color: CyberTheme.warning,
          titleSize: 16,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'El contador de misión volverá a 0/$_groupsPerAccount. Tus grupos no se tocan.',
              style: CyberTheme.mono(fontSize: 12, color: CyberTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RetroButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.of(ctx).pop(),
                  backgroundColor: CyberTheme.surfaceVariant,
                  textColor: CyberTheme.text,
                ),
                const SizedBox(width: 14),
                RetroButton(
                  label: 'Reiniciar',
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      _agregadosSesion = 0;
                      _misionCompletada = false;
                    });
                    _guardarDatos();
                    _mostrarMensaje('CONTADOR REINICIADO', isError: false);
                  },
                  backgroundColor: CyberTheme.warning,
                  textColor: Colors.black,
                  borderColor: CyberTheme.warning,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ----------------------------------------------------
  // IMPORT / EXPORT / SHARE
  // ----------------------------------------------------
  Future<void> _compartirJSON() async {
    _vibrar(durationMs: 30);
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(_grupos.map((g) => g.toJson()).toList());
    await SharePlus.instance.share(
      ShareParams(text: jsonStr, subject: 'cyber_grupos.json'),
    );
  }

  Future<void> _exportarJSON() async {
    _vibrar(durationMs: 25);
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(_grupos.map((g) => g.toJson()).toList());
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/cyber_grupos.json');
      await file.writeAsString(jsonStr);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: 'Respaldo Cyber FB Manager',
          subject: 'cyber_grupos.json',
        ),
      );
      _mostrarMensaje('RESPALDO PREPARADO', isError: false);
    } catch (e) {
      _mostrarMensaje('ERROR AL EXPORTAR', isError: true);
    }
  }

  Future<void> _importarJSON() async {
    String rawContent;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt', 'csv'],
      );
      if (files.isEmpty) return;

      final file = files.first;
      rawContent = await file.xFile.readAsString();
    } catch (e) {
      _mostrarMensaje('ARCHIVO NO VÁLIDO', isError: true);
      return;
    }
    if (!mounted) return;
    await _procesarImportacion(rawContent);
  }

  /// Punto único de entrada para importar: lee el contenido con el lector
  /// universal, muestra un resumen y deja elegir Fusionar o Reemplazar.
  Future<void> _procesarImportacion(String raw) async {
    final lectura = UniversalImporter.parse(raw);
    if (lectura.items.isEmpty) {
      _vibrar(durationMs: 50);
      _mostrarMensaje('NO SE ENCONTRARON GRUPOS', isError: true);
      return;
    }

    final simulacion = fusionarGrupos(_grupos, lectura.items);
    final repetidos = simulacion.repetidos + lectura.duplicadosEnArchivo;

    _vibrar(durationMs: 25);
    final accion = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return CyberDialog(
          title: 'IMPORTAR DATOS',
          color: CyberTheme.primary,
          titleSize: 16,
          children: [
            Text(
              'FORMATO: ${lectura.formato.toUpperCase()}\n'
              'DETECTADOS: ${lectura.detectados}\n'
              'NUEVOS: ${simulacion.nuevos}\n'
              'REPETIDOS: $repetidos\n'
              'INVÁLIDOS: ${lectura.invalidos}',
              style: CyberTheme.mono(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'FUSIONAR añade solo los nuevos y conserva tus calificaciones.\n'
              'REEMPLAZAR descarta tu lista actual (se puede deshacer).',
              style: CyberTheme.mono(fontSize: 11, color: CyberTheme.textMuted),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                RetroButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.of(ctx).pop(),
                  backgroundColor: CyberTheme.surfaceVariant,
                  textColor: CyberTheme.text,
                ),
                RetroButton(
                  label: 'Reemplazar',
                  onPressed: () => Navigator.of(ctx).pop('replace'),
                  backgroundColor: CyberTheme.bg,
                  textColor: CyberTheme.warning,
                  borderColor: CyberTheme.warning,
                ),
                RetroButton(
                  label: 'Fusionar',
                  onPressed: () => Navigator.of(ctx).pop('merge'),
                  backgroundColor: CyberTheme.primary,
                  textColor: Colors.black,
                  borderColor: CyberTheme.primary,
                ),
              ],
            ),
          ],
        );
      },
    );

    if (!mounted || accion == null) return;

    _vibrar(durationMs: 30);
    final previa = _grupos.map((g) => g.copy()).toList();
    _guardarSnapshot();
    _guardarBackup(previa);

    if (accion == 'merge') {
      setState(() {
        _grupos = simulacion.items;
      });
      _guardarDatos();
      final adoptados = simulacion.estadosAdoptados > 0
          ? ' · ESTADOS: +${simulacion.estadosAdoptados}'
          : '';
      _mostrarMensaje(
        'FUSIONADO: +${simulacion.nuevos} NUEVOS · $repetidos REPETIDOS$adoptados',
        isError: false,
        deshacer: true,
      );
    } else {
      setState(() {
        _grupos = lectura.items;
      });
      _guardarDatos();
      _mostrarMensaje(
        'LISTA REEMPLAZADA: ${lectura.items.length} GRUPOS',
        isError: false,
        deshacer: true,
      );
    }
  }

  // ----------------------------------------------------
  // MODALS
  // ----------------------------------------------------
  void _abrirModalConfirmarEliminar(int globalIndex) {
    _vibrar(durationMs: 30);
    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return CyberDialog(
          title: 'ELIMINAR GRUPO',
          color: CyberTheme.error,
          titleSize: 18,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Podrás deshacerlo justo después de borrar.',
              style: CyberTheme.mono(fontSize: 13, color: CyberTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RetroButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.of(ctx).pop(),
                  backgroundColor: CyberTheme.surfaceVariant,
                  textColor: CyberTheme.text,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                const SizedBox(width: 14),
                RetroButton(
                  label: 'Borrar',
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _vibrar(durationMs: 50);
                    _guardarSnapshot();
                    setState(() {
                      if (_esActual(_grupos[globalIndex])) {
                        _urlActual = '';
                      }
                      _grupos.removeAt(globalIndex);
                    });
                    _guardarDatos();
                    _mostrarMensaje(
                      'ELIMINADO',
                      isError: false,
                      deshacer: true,
                    );
                  },
                  backgroundColor: CyberTheme.error,
                  textColor: Colors.black,
                  borderColor: CyberTheme.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _abrirModalReemplazar(int globalIndex) {
    _vibrar(durationMs: 20);
    final urlOriginal = _grupos[globalIndex].url;

    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return TextControllerScope(
          initialText: urlOriginal,
          builder: (ctx, editController) {
            return CyberDialog(
              title: 'REEMPLAZAR GRUPO',
              color: CyberTheme.primary,
              titleSize: 16,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: CyberTheme.bg,
                    border: Border.all(color: CyberTheme.border, width: 2),
                  ),
                  child: TextField(
                    controller: editController,
                    autofocus: true,
                    style: CyberTheme.mono(fontSize: 13),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(10),
                      border: InputBorder.none,
                      hintText: 'PEGA EL NUEVO ENLACE...',
                      hintStyle: TextStyle(
                        fontFamily: 'monospace',
                        color: CyberTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    RetroButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(ctx).pop(),
                      backgroundColor: CyberTheme.surfaceVariant,
                      textColor: CyberTheme.text,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    const SizedBox(width: 10),
                    RetroButton(
                      label: 'Guardar',
                      onPressed: () {
                        final raw = editController.text.trim();
                        if (raw.isEmpty) return;
                        final link = FBUrlHelper.sanearUrl(raw);
                        final idNuevo = FBUrlHelper.limpiarID(link);
                        if (idNuevo.isEmpty) {
                          _vibrar(durationMs: 50);
                          _mostrarMensaje('ENLACE NO VÁLIDO', isError: true);
                          return;
                        }
                        if (_existeDuplicado(link, ignorarIndex: globalIndex)) {
                          _vibrar(durationMs: 60);
                          _mostrarMensaje('GRUPO REPETIDO', isError: true);
                          return;
                        }

                        Navigator.of(ctx).pop();
                        _vibrar(durationMs: 25);
                        _guardarSnapshot();
                        setState(() {
                          if (_esActual(_grupos[globalIndex])) {
                            _urlActual = link;
                          }
                          _grupos[globalIndex] = GroupItem(
                            url: link,
                            status: 'none',
                          );
                        });
                        _guardarDatos();
                        _mostrarMensaje(
                          'REEMPLAZADO',
                          isError: false,
                          deshacer: true,
                        );
                      },
                      backgroundColor: CyberTheme.primary,
                      textColor: Colors.black,
                      borderColor: CyberTheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirModalTexto() {
    _vibrar(durationMs: 20);
    final textoInicial = jsonEncode(_grupos.map((g) => g.toJson()).toList());

    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return TextControllerScope(
          initialText: textoInicial,
          builder: (ctx, textController) {
            return CyberDialog(
              title: 'RESPALDO EN TEXTO',
              color: CyberTheme.primary,
              titleSize: 16,
              hPadding: 16,
              children: [
                Text(
                  'Pega aquí cualquier JSON, lista de enlaces o CSV para importarlo.',
                  style: CyberTheme.mono(
                    fontSize: 11,
                    color: CyberTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: CyberTheme.bg,
                    border: Border.all(color: CyberTheme.border, width: 2),
                  ),
                  child: TextField(
                    controller: textController,
                    maxLines: null,
                    expands: true,
                    style: CyberTheme.mono(fontSize: 11),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RetroButton(
                      label: 'Copiar',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: textController.text),
                        );
                        _vibrar(durationMs: 20);
                        _mostrarMensaje(
                          'COPIADO AL PORTAPAPELES',
                          isError: false,
                        );
                      },
                      backgroundColor: CyberTheme.surfaceVariant,
                      textColor: CyberTheme.text,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RetroButton(
                          label: 'Cerrar',
                          onPressed: () => Navigator.of(ctx).pop(),
                          backgroundColor: CyberTheme.surfaceVariant,
                          textColor: CyberTheme.textMuted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        RetroButton(
                          label: 'Importar',
                          onPressed: () {
                            final texto = textController.text;
                            Navigator.of(ctx).pop();
                            _procesarImportacion(texto);
                          },
                          backgroundColor: CyberTheme.primary,
                          textColor: Colors.black,
                          borderColor: CyberTheme.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirModalGruposPorCuenta() {
    _vibrar(durationMs: 20);
    String? validationError;
    const List<int> presets = [10, 15, 20, 25, 30];

    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return TextControllerScope(
          initialText: '$_groupsPerAccount',
          builder: (ctx, limitController) {
            return StatefulBuilder(
              builder: (ctx, setModalState) {
                void aplicarValor() {
                  final raw = limitController.text.trim();
                  final parsed = int.tryParse(raw);
                  if (parsed == null || parsed < 1) {
                    _vibrar(durationMs: 50);
                    setModalState(() {
                      validationError = 'MÍNIMO 1 GRUPO POR CUENTA';
                    });
                    _mostrarMensaje('MÍNIMO 1 GRUPO POR CUENTA', isError: true);
                    return;
                  }
                  Navigator.of(ctx).pop();
                  _actualizarGruposPorCuenta(parsed);
                }

                return CyberDialog(
                  title: 'GRUPOS POR CUENTA',
                  color: CyberTheme.primary,
                  titleSize: 16,
                  hPadding: 16,
                  children: [
                    Text(
                      'Configura la cantidad de grupos asignados por perfil/cuenta (mínimo 1).',
                      style: CyberTheme.mono(
                        fontSize: 12,
                        color: CyberTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: CyberTheme.bg,
                        border: Border.all(
                          color: validationError != null
                              ? CyberTheme.error
                              : CyberTheme.border,
                          width: 2,
                        ),
                      ),
                      child: TextField(
                        key: const Key('groups_per_account_input'),
                        controller: limitController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        style: CyberTheme.mono(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        onChanged: (_) {
                          if (validationError != null) {
                            setModalState(() {
                              validationError = null;
                            });
                          }
                        },
                        onSubmitted: (_) => aplicarValor(),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(10),
                          border: InputBorder.none,
                          hintText: 'EJ. 10, 15, 20, 25, 30...',
                          hintStyle: TextStyle(
                            fontFamily: 'monospace',
                            color: CyberTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: CyberTheme.mono(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: CyberTheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: presets.map((preset) {
                        final isSelected =
                            limitController.text.trim() == '$preset';
                        return RetroPillButton(
                          label: '$preset',
                          isActive: isSelected,
                          activeBg: CyberTheme.primary,
                          activeColor: Colors.black,
                          onTap: () {
                            _vibrar(durationMs: 15);
                            setModalState(() {
                              limitController.text = '$preset';
                              validationError = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    RetroButton(
                      label: 'Restablecer a 25',
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _actualizarGruposPorCuenta(
                          _defaultGroupsPerAccount,
                          mensaje: 'RESTABLECIDO A 25 GRUPOS/CUENTA',
                        );
                      },
                      backgroundColor: CyberTheme.bg,
                      textColor: CyberTheme.warning,
                      borderColor: CyberTheme.warning,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        RetroButton(
                          label: 'Cancelar',
                          onPressed: () => Navigator.of(ctx).pop(),
                          backgroundColor: CyberTheme.surfaceVariant,
                          textColor: CyberTheme.text,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        const SizedBox(width: 10),
                        RetroButton(
                          label: 'Guardar',
                          onPressed: aplicarValor,
                          backgroundColor: CyberTheme.primary,
                          textColor: Colors.black,
                          borderColor: CyberTheme.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _abrirMenuDatos(BuildContext btnContext) async {
    _vibrar(durationMs: 20);
    final box = btnContext.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(btnContext).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    PopupMenuItem<String> item(String value, String label, IconData icon) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 16, color: CyberTheme.primary),
            const SizedBox(width: 10),
            Text(label, style: CyberTheme.mono(fontSize: 12)),
          ],
        ),
      );
    }

    final seleccion = await showMenu<String>(
      context: btnContext,
      position: position,
      color: CyberTheme.surface,
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: CyberTheme.primary, width: 2),
      ),
      items: [
        item('share', 'COMPARTIR', Icons.share),
        item('save', 'GUARDAR EN ARCHIVO', Icons.save_alt),
        item('load', 'CARGAR ARCHIVO', Icons.folder_open),
        item('text', 'TEXTO / IMPORTAR', Icons.text_snippet),
      ],
    );

    if (!mounted) return;
    switch (seleccion) {
      case 'share':
        await _compartirJSON();
      case 'save':
        await _exportarJSON();
      case 'load':
        await _importarJSON();
      case 'text':
        _abrirModalTexto();
    }
  }

  // ----------------------------------------------------
  // BUILD
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final total = _grupos.length;
    final totalCuentas = total == 0
        ? 1
        : ((total + _groupsPerAccount - 1) ~/ _groupsPerAccount);
    final visibles = _calcularVisibles();

    return Scaffold(
      body: SafeArea(
        child: ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 80),
          itemCount: 1 + (visibles.isEmpty ? 1 : visibles.length),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildTopControlPanel(total, totalCuentas);
            }

            if (visibles.isEmpty) {
              return total == 0
                  ? _buildCuentaVacia(
                      titulo: 'CUENTA 1',
                      badge: '0/$_groupsPerAccount',
                      mensaje: 'SIN GRUPOS EN ESTA CUENTA',
                    )
                  : _buildCuentaVacia(
                      titulo: 'FILTRO',
                      badge: '0/$total',
                      mensaje: 'NINGÚN GRUPO COINCIDE CON EL FILTRO',
                    );
            }

            final pos = index - 1;
            final globalIdx = visibles[pos];
            final item = _grupos[globalIdx];
            final localNum = (globalIdx % _groupsPerAccount) + 1;
            final cuentaNumero = (globalIdx ~/ _groupsPerAccount) + 1;
            final isFirstInCuenta =
                pos == 0 ||
                (visibles[pos - 1] ~/ _groupsPerAccount) != (cuentaNumero - 1);
            final isLastInCuenta =
                pos == visibles.length - 1 ||
                (visibles[pos + 1] ~/ _groupsPerAccount) != (cuentaNumero - 1);

            return _buildGroupItemRow(
              item: item,
              localNum: localNum,
              globalIdx: globalIdx,
              cuentaNumero: cuentaNumero,
              isFirstInCuenta: isFirstInCuenta,
              isLastInCuenta: isLastInCuenta,
              total: total,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _irAlActual,
        backgroundColor: CyberTheme.error,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Colors.white, width: 2),
        ),
        elevation: 6,
        tooltip: 'Ir al Actual',
        child: const Icon(Icons.my_location, size: 26),
      ),
    );
  }

  // ==========================================
  // TOP PANEL WIDGETS
  // ==========================================
  Widget _buildConteos(List<int> c, {double fontSize = 11}) {
    TextSpan span(String t, Color color) => TextSpan(
      text: t,
      style: TextStyle(color: color),
    );
    return Text.rich(
      TextSpan(
        style: CyberTheme.mono(fontSize: fontSize, fontWeight: FontWeight.bold),
        children: [
          span('✔${c[0]}', CyberTheme.secondary),
          span('  ~${c[1]}', CyberTheme.warning),
          span('  ✘${c[2]}', CyberTheme.error),
          span('  ?${c[3]}', CyberTheme.textMuted),
        ],
      ),
    );
  }

  Widget _buildTopControlPanel(int total, int totalCuentas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Título principal Cyberpunk
        Text(
          'CYBER FB MANAGER PRO',
          textAlign: TextAlign.center,
          style: CyberTheme.mono(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: CyberTheme.primary,
          ),
        ),
        const SizedBox(height: 4),

        // Contador estadístico
        Text(
          'TOTAL: $total GRUPOS • CUENTAS: $totalCuentas • $_groupsPerAccount/CTA',
          textAlign: TextAlign.center,
          style: CyberTheme.mono(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: CyberTheme.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Center(child: _buildConteos(_conteoEstados(0, total), fontSize: 12)),
        const SizedBox(height: 12),

        // Radar de Misión (8-Bits Tracker)
        _buildMissionRadar(total),

        // Panel de Entrada y Acciones
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CyberTheme.surface,
            border: Border.all(color: CyberTheme.border, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF333333),
                offset: Offset(4, 4),
                blurRadius: 0,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fila de Entrada de Enlace
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      decoration: BoxDecoration(
                        color: CyberTheme.bg,
                        border: Border.all(color: CyberTheme.border, width: 2),
                      ),
                      child: TextField(
                        controller: _urlController,
                        style: CyberTheme.mono(fontSize: 13),
                        minLines: 1,
                        maxLines: 3,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _agregarGrupo(),
                        decoration: InputDecoration(
                          hintText: 'PEGA EL ENLACE (O VARIOS)...',
                          hintStyle: const TextStyle(
                            fontFamily: 'monospace',
                            color: CyberTheme.textMuted,
                            fontSize: 12,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          suffixIcon: Tooltip(
                            message: 'Pegar del portapapeles',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _pegarDelPortapapeles,
                              child: const Icon(
                                Icons.content_paste,
                                size: 18,
                                color: CyberTheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RetroButton(
                    label: 'Añadir',
                    onPressed: _agregarGrupo,
                    backgroundColor: CyberTheme.primary,
                    textColor: Colors.black,
                    borderColor: CyberTheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Botones de acciones en grid horizontal envolvente
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  RetroButton(
                    label: 'Ir al Actual',
                    onPressed: _irAlActual,
                    backgroundColor: CyberTheme.error,
                    textColor: Colors.black,
                    borderColor: CyberTheme.error,
                  ),
                  RetroButton(
                    label: 'Siguiente',
                    onPressed: _abrirSiguienteSinCalificar,
                    backgroundColor: CyberTheme.secondary,
                    textColor: Colors.black,
                    borderColor: CyberTheme.secondary,
                  ),
                  RetroButton(
                    label: 'Aleatorizar',
                    onPressed: _confirmarAleatorizarGrupos,
                    backgroundColor: CyberTheme.bg,
                    textColor: CyberTheme.primary,
                    borderColor: CyberTheme.primary,
                  ),
                  RetroButton(
                    label: 'Grupos por cuenta',
                    onPressed: _abrirModalGruposPorCuenta,
                    backgroundColor: CyberTheme.bg,
                    textColor: CyberTheme.warning,
                    borderColor: CyberTheme.warning,
                  ),
                  Builder(
                    builder: (btnContext) => RetroButton(
                      label: 'Datos ▾',
                      onPressed: () => _abrirMenuDatos(btnContext),
                      backgroundColor: CyberTheme.surfaceVariant,
                      textColor: CyberTheme.text,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              _buildFiltroBar(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroBar() {
    Widget chip(String label, String valor, Color color, Color activeBg) {
      return RetroPillButton(
        label: label,
        isActive: _filtroEstado == valor,
        activeBg: activeBg,
        activeColor: color,
        textColor: color,
        onTap: () {
          _vibrar(durationMs: 15);
          setState(() => _filtroEstado = valor);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: CyberTheme.bg,
            border: Border.all(color: CyberTheme.border, width: 2),
          ),
          child: TextField(
            controller: _searchController,
            style: CyberTheme.mono(fontSize: 12),
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: InputDecoration(
              hintText: 'BUSCAR EN LA LISTA...',
              hintStyle: const TextStyle(
                fontFamily: 'monospace',
                color: CyberTheme.textMuted,
                fontSize: 11,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: InputBorder.none,
              prefixIcon: const Icon(
                Icons.search,
                size: 16,
                color: CyberTheme.textMuted,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _searchController.clear();
                        setState(() => _busqueda = '');
                      },
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: CyberTheme.textMuted,
                      ),
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip('Todos', 'all', CyberTheme.primary, CyberTheme.currentBg),
            chip(
              'Sin calif.',
              'none',
              CyberTheme.text,
              CyberTheme.surfaceVariant,
            ),
            chip(
              'Bien',
              'good',
              CyberTheme.secondary,
              CyberTheme.greenActiveBg,
            ),
            chip(
              'Medio',
              'regular',
              CyberTheme.warning,
              CyberTheme.yellowActiveBg,
            ),
            chip('Mal', 'bad', CyberTheme.error, CyberTheme.redActiveBg),
            RetroPillButton(
              label: 'Auto ▶',
              isActive: _autoAvanzar,
              activeBg: const Color(0xFF00F0FF),
              activeColor: Colors.black,
              onTap: _toggleAutoAvanzar,
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // RADAR DE MISIÓN (ESTILO 8-BITS)
  // ==========================================
  Widget _buildMissionRadar(int totalGrupos) {
    if (_misionCompletada) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CyberTheme.trackerBg,
          border: Border.all(color: CyberTheme.secondary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x334CAF50),
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          '¡MISIÓN CUMPLIDA! 👾',
          textAlign: TextAlign.center,
          style: CyberTheme.mono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: CyberTheme.secondary,
          ),
        ),
      );
    }

    final int faltan = FBUrlHelper.calcularFaltan(
      totalGrupos,
      _groupsPerAccount,
    );

    return CustomPaint(
      painter: DashedBorderPainter(
        color: CyberTheme.secondary,
        strokeWidth: 2,
        dashLength: 5,
        dashSpace: 4,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(10),
        color: CyberTheme.trackerBg,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 56),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: CyberTheme.mono(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: CyberTheme.text,
                      ),
                      children: [
                        const TextSpan(text: 'MISIÓN: '),
                        TextSpan(
                          text: '$_agregadosSesion',
                          style: const TextStyle(color: CyberTheme.primary),
                        ),
                        TextSpan(text: '/$_groupsPerAccount AÑADIDOS'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: RetroPillButton(
                    label: '↺',
                    isActive: false,
                    textColor: CyberTheme.warning,
                    borderColor: CyberTheme.warning,
                    onTap: _confirmarReiniciarMision,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (faltan > 0)
              Text(
                'FALTAN $faltan GRUPOS PARA CERRAR LA CUENTA ACTUAL',
                textAlign: TextAlign.center,
                style: CyberTheme.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: CyberTheme.warning,
                ),
              )
            else if (totalGrupos > 0)
              Text(
                'LAS CUENTAS ESTÁN LLENAS (MÚLTIPLO DE $_groupsPerAccount)',
                textAlign: TextAlign.center,
                style: CyberTheme.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: CyberTheme.secondary,
                ),
              )
            else
              Text(
                'AÚN NO HAY GRUPOS EN LA LISTA',
                textAlign: TextAlign.center,
                style: CyberTheme.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: CyberTheme.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CUENTA CARD & ITEMS
  // ==========================================
  Widget _buildCuentaVacia({
    required String titulo,
    required String badge,
    required String mensaje,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: CyberTheme.surface,
        border: Border.all(color: CyberTheme.border, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF333333),
            offset: Offset(5, 5),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: CyberTheme.surfaceVariant,
              border: Border(
                bottom: BorderSide(color: CyberTheme.border, width: 3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titulo,
                  style: CyberTheme.mono(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: CyberTheme.primary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CyberTheme.bg,
                    border: Border.all(color: CyberTheme.border, width: 2),
                  ),
                  child: Text(
                    badge,
                    style: CyberTheme.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: CyberTheme.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              mensaje,
              textAlign: TextAlign.center,
              style: CyberTheme.mono(fontSize: 11, color: CyberTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuentaHeader({
    required int cuentaNumero,
    required int startIdx,
    required int endIdx,
  }) {
    final cuentaLength = endIdx - startIdx;
    final isFull = cuentaLength == _groupsPerAccount;

    return Container(
      margin: cuentaNumero > 1
          ? const EdgeInsets.only(top: 16)
          : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: CyberTheme.surfaceVariant,
        border: Border(
          top: BorderSide(color: CyberTheme.border, width: 3),
          left: BorderSide(color: CyberTheme.border, width: 3),
          right: BorderSide(color: CyberTheme.border, width: 3),
          bottom: BorderSide(color: CyberTheme.border, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF333333),
            offset: Offset(5, 0),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 2,
              children: [
                Text(
                  'CUENTA $cuentaNumero',
                  style: CyberTheme.mono(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: CyberTheme.primary,
                  ),
                ),
                _buildConteos(_conteoEstados(startIdx, endIdx), fontSize: 11),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isFull ? CyberTheme.greenActiveBg : CyberTheme.bg,
              border: Border.all(
                color: isFull ? CyberTheme.secondary : CyberTheme.border,
                width: 2,
              ),
            ),
            child: Text(
              '$cuentaLength/$_groupsPerAccount',
              style: CyberTheme.mono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isFull ? CyberTheme.secondary : CyberTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupItemRow({
    required GroupItem item,
    required int localNum,
    required int globalIdx,
    required int cuentaNumero,
    required bool isFirstInCuenta,
    required bool isLastInCuenta,
    required int total,
  }) {
    Widget? accountHeader;
    if (isFirstInCuenta) {
      final startIdx = (cuentaNumero - 1) * _groupsPerAccount;
      final endIdx = min(startIdx + _groupsPerAccount, total);
      accountHeader = _buildCuentaHeader(
        cuentaNumero: cuentaNumero,
        startIdx: startIdx,
        endIdx: endIdx,
      );
    }

    final groupRowContent = _buildGroupRow(
      item,
      localNum,
      globalIdx,
      isLastInCuenta,
    );

    final rowContainer = Container(
      decoration: BoxDecoration(
        color: CyberTheme.surface,
        border: Border(
          left: const BorderSide(color: CyberTheme.border, width: 3),
          right: const BorderSide(color: CyberTheme.border, width: 3),
          bottom: isLastInCuenta
              ? const BorderSide(color: CyberTheme.border, width: 3)
              : BorderSide.none,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF333333),
            offset: Offset(5, isLastInCuenta ? 5 : 0),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: groupRowContent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [?accountHeader, rowContainer],
    );
  }

  Widget _buildGroupRow(
    GroupItem item,
    int localNum,
    int globalIdx,
    bool isLast,
  ) {
    final bool isCurrent = _esActual(item);

    // Colores y bordes según estado
    Color? leftBorderColor;
    if (item.status == 'good') {
      leftBorderColor = CyberTheme.secondary;
    } else if (item.status == 'regular') {
      leftBorderColor = CyberTheme.warning;
    } else if (item.status == 'bad') {
      leftBorderColor = CyberTheme.error;
    }

    final bool isBad = item.status == 'bad';

    return Container(
      margin: isCurrent
          ? const EdgeInsets.symmetric(vertical: 5, horizontal: 2)
          : EdgeInsets.zero,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF001F4D) : Colors.transparent,
        border: isCurrent
            ? Border.all(color: const Color(0xFF00F0FF), width: 2.5)
            : Border(
                left: leftBorderColor != null
                    ? BorderSide(color: leftBorderColor, width: 6)
                    : BorderSide.none,
                bottom: !isLast
                    ? const BorderSide(color: CyberTheme.border, width: 1)
                    : BorderSide.none,
              ),
        boxShadow: isCurrent
            ? const [
                BoxShadow(
                  color: Color(0xFF00F0FF),
                  offset: Offset(3, 3),
                  blurRadius: 0,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(1, 1),
                  blurRadius: 0,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila del Enlace
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$localNum.',
                style: CyberTheme.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isCurrent
                      ? const Color(0xFF00F0FF)
                      : CyberTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _abrirEnFB(item.url),
                  onLongPress: () => _copiarEnlace(item.url),
                  child: Opacity(
                    opacity: isBad ? 0.7 : 1.0,
                    child: Text(
                      item.url,
                      style: CyberTheme.mono(
                        fontSize: 12,
                        color: isCurrent
                            ? const Color(0xFF00F0FF)
                            : CyberTheme.primary,
                        decoration: isBad
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(1.5, 1.5),
                        blurRadius: 0,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Text(
                    '⚡ ACTUAL',
                    style: CyberTheme.mono(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),

          // Botones de acción del ítem con micro-interacción activa
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // Botón Fijar
                RetroPillButton(
                  label: 'Fijar',
                  isActive: isCurrent,
                  activeBg: const Color(0xFF00F0FF),
                  activeColor: Colors.black,
                  onTap: () => _marcarActual(item.url),
                ),
                // Botón Bien
                RetroPillButton(
                  label: 'Bien',
                  isActive: item.status == 'good',
                  activeBg: CyberTheme.greenActiveBg,
                  activeColor: CyberTheme.secondary,
                  onTap: () => _toggleCalificacion(globalIdx, 'good'),
                ),
                // Botón Medio
                RetroPillButton(
                  label: 'Medio',
                  isActive: item.status == 'regular',
                  activeBg: CyberTheme.yellowActiveBg,
                  activeColor: CyberTheme.warning,
                  onTap: () => _toggleCalificacion(globalIdx, 'regular'),
                ),
                // Botón Mal
                RetroPillButton(
                  label: 'Mal',
                  isActive: item.status == 'bad',
                  activeBg: CyberTheme.redActiveBg,
                  activeColor: CyberTheme.error,
                  onTap: () => _toggleCalificacion(globalIdx, 'bad'),
                ),
                // Botón Cambio
                RetroPillButton(
                  label: 'Cambio',
                  isActive: false,
                  onTap: () => _abrirModalReemplazar(globalIdx),
                ),
                // Botón Borrar ✕
                RetroPillButton(
                  label: '✕',
                  isActive: false,
                  textColor: CyberTheme.error,
                  borderColor: Colors.transparent,
                  onTap: () => _abrirModalConfirmarEliminar(globalIdx),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// DIÁLOGO CYBER REUTILIZABLE
// ==========================================
class CyberDialog extends StatelessWidget {
  final String title;
  final Color color;
  final double titleSize;
  final double hPadding;
  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget> children;

  const CyberDialog({
    super.key,
    required this.title,
    required this.color,
    required this.children,
    this.titleSize = 16,
    this.hPadding = 20,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: CyberTheme.surface,
      shape: BeveledRectangleBorder(side: BorderSide(color: color, width: 3)),
      insetPadding: EdgeInsets.symmetric(horizontal: hPadding),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment == CrossAxisAlignment.center
              ? CrossAxisAlignment.stretch
              : crossAxisAlignment,
          children: [
            Text(
              title,
              textAlign: crossAxisAlignment == CrossAxisAlignment.center
                  ? TextAlign.center
                  : TextAlign.start,
              style: CyberTheme.mono(
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(
              height: crossAxisAlignment == CrossAxisAlignment.center ? 12 : 14,
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Crea y libera un [TextEditingController] atado al ciclo de vida del widget
/// (se descarta cuando el diálogo desaparece del árbol, tras la animación).
class TextControllerScope extends StatefulWidget {
  final String initialText;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  const TextControllerScope({
    super.key,
    required this.initialText,
    required this.builder,
  });

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

// ==========================================
// REUSABLE RETRO PILL BUTTON (TACTILE ACTIVE)
// ==========================================
class RetroPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? activeBg;
  final Color? activeColor;
  final Color? textColor;
  final Color? borderColor;

  const RetroPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.activeBg,
    this.activeColor,
    this.textColor,
    this.borderColor,
  });

  @override
  State<RetroPillButton> createState() => _RetroPillButtonState();
}

class _RetroPillButtonState extends State<RetroPillButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final Color bg = widget.isActive
        ? (widget.activeBg ?? CyberTheme.primary)
        : CyberTheme.bg;
    final Color border = widget.isActive
        ? (widget.activeColor ?? CyberTheme.primary)
        : (widget.borderColor ?? CyberTheme.border);
    final Color fg = widget.isActive
        ? (widget.activeColor ?? Colors.black)
        : (widget.textColor ?? CyberTheme.textMuted);

    final offset = _isPressed ? const Offset(2, 2) : Offset.zero;
    final shadowOffset = _isPressed
        ? const Offset(0.5, 0.5)
        : const Offset(2, 2);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: Transform.translate(
        offset: offset,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black,
                offset: shadowOffset,
                blurRadius: 0,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: CyberTheme.mono(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// REUSABLE RETRO BUTTON (TACTILE ACTIVE)
// ==========================================
class RetroButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color textColor;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const RetroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = const Color(0xFF222222),
    this.textColor = const Color(0xFFEEEEEE),
    this.borderColor = const Color(0xFF444444),
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.fontSize = 11,
  });

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final offset = _isPressed ? const Offset(2, 2) : Offset.zero;
    final shadowOffset = _isPressed ? const Offset(1, 1) : const Offset(3, 3);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: Transform.translate(
        offset: offset,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            border: Border.all(color: widget.borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black,
                offset: shadowOffset,
                blurRadius: 0,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Text(
            widget.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: widget.fontSize,
              fontWeight: FontWeight.bold,
              color: widget.textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PAINTER PARA EL BORDE DISCONTINUO DEL RADAR
// ==========================================
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashSpace;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.dashLength = 5.0,
    this.dashSpace = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    _drawDashedLine(canvas, paint, const Offset(0, 0), Offset(size.width, 0));
    _drawDashedLine(
      canvas,
      paint,
      Offset(size.width, 0),
      Offset(size.width, size.height),
    );
    _drawDashedLine(
      canvas,
      paint,
      Offset(size.width, size.height),
      Offset(0, size.height),
    );
    _drawDashedLine(canvas, paint, Offset(0, size.height), const Offset(0, 0));
  }

  void _drawDashedLine(Canvas canvas, Paint paint, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance == 0) return;
    final unitX = dx / distance;
    final unitY = dy / distance;

    double currentDist = 0.0;
    while (currentDist < distance) {
      final step = min(dashLength, distance - currentDist);
      canvas.drawLine(
        Offset(start.dx + unitX * currentDist, start.dy + unitY * currentDist),
        Offset(
          start.dx + unitX * (currentDist + step),
          start.dy + unitY * (currentDist + step),
        ),
        paint,
      );
      currentDist += dashLength + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.dashSpace != dashSpace;
  }
}
