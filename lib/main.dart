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
// MODEL
// ==========================================
class GroupItem {
  String url;
  String status; // 'good', 'regular', 'bad', 'none'

  GroupItem({required this.url, this.status = 'none'});

  factory GroupItem.fromJson(dynamic json) {
    if (json is String) {
      return GroupItem(url: json, status: 'none');
    }
    if (json is Map) {
      final url = (json['url'] ?? json['link'] ?? '').toString();
      final status = (json['status'] ?? 'none').toString();
      return GroupItem(url: url, status: status);
    }
    return GroupItem(url: '', status: 'none');
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'status': status,
  };
}

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

class _FBManagerScreenState extends State<FBManagerScreen> {
  final TextEditingController _urlController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<GroupItem> _grupos = [];
  String _urlActual = '';
  int _agregadosSesion = 0;

  String? _statusMessage;
  bool _statusIsError = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _urlController.dispose();
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
    final rawList = prefs.getString('cyber_fb_list');
    final curr = prefs.getString('cyber_fb_current_url') ?? '';

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
      });
    } else {
      _grupos = parsed;
      _urlActual = currSaneada;
    }

    if (seModificaronUrls) {
      final encoded = jsonEncode(parsed.map((g) => g.toJson()).toList());
      await prefs.setString('cyber_fb_list', encoded);
      await prefs.setString('cyber_fb_current_url', currSaneada);
    }
  }

  Future<void> _guardarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_grupos.map((g) => g.toJson()).toList());
    await prefs.setString('cyber_fb_list', encoded);
    await prefs.setString('cyber_fb_current_url', _urlActual);
  }

  // ----------------------------------------------------
  // NOTIFICATIONS / STATUS
  // ----------------------------------------------------
  void _mostrarMensaje(String texto, {required bool isError}) {
    _statusTimer?.cancel();
    setState(() {
      _statusMessage = texto;
      _statusIsError = isError;
    });
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  // ----------------------------------------------------
  // BUSINESS LOGIC
  // ----------------------------------------------------
  void _agregarGrupo() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;

    final sanitized = FBUrlHelper.sanearUrl(raw);
    final idNuevo = FBUrlHelper.limpiarID(sanitized);
    if (idNuevo.isEmpty) {
      _vibrar(durationMs: 50);
      _mostrarMensaje('ENLACE NO VÁLIDO', isError: true);
      return;
    }

    for (final g in _grupos) {
      if (FBUrlHelper.limpiarID(g.url) == idNuevo) {
        _vibrar(durationMs: 60);
        _mostrarMensaje('GRUPO REPETIDO', isError: true);
        return;
      }
    }

    _vibrar(durationMs: 25);

    // Reemplazo automático si existe alguno marcado como 'bad'
    final indexMalo = _grupos.indexWhere((g) => g.status == 'bad');
    if (indexMalo != -1) {
      final cuenta = (indexMalo ~/ 25) + 1;
      final posEnCuenta = (indexMalo % 25) + 1;
      final urlAnterior = _grupos[indexMalo].url;

      _grupos[indexMalo] = GroupItem(url: sanitized, status: 'none');
      _mostrarMensaje(
        'REEMPLAZADO EN CUENTA $cuenta (#$posEnCuenta)',
        isError: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CyberTheme.surface,
            shape: Border.all(color: CyberTheme.secondary, width: 2),
            duration: const Duration(seconds: 4),
            content: Text(
              'Reemplazado en Cuenta $cuenta (Posición #$posEnCuenta)\nAnterior: $urlAnterior',
              style: CyberTheme.mono(
                color: CyberTheme.secondary,
                fontSize: 12,
              ),
            ),
          ),
        );
      }
    } else {
      _grupos.add(GroupItem(url: sanitized, status: 'none'));
      _mostrarMensaje('AÑADIDO', isError: false);
    }

    // Progreso de misión diaria/sesión
    if (_agregadosSesion < 25) {
      _agregadosSesion++;
      if (_agregadosSesion == 25) {
        _reproducirSonidoVictoria();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _agregadosSesion = 26; // Oculta tras meta cumplida
            });
          }
        });
      }
    }

    _urlController.clear();
    _guardarDatos();
    setState(() {});
  }

  void _marcarActual(String url) {
    _vibrar(durationMs: 20);
    setState(() {
      _urlActual = url;
    });
    _guardarDatos();
  }

  void _irAlActual() {
    _vibrar(durationMs: 35);
    if (_urlActual.isEmpty) {
      _mostrarMensaje('SIN GRUPO ACTUAL', isError: true);
      return;
    }

    final index = _grupos.indexWhere((g) => g.url == _urlActual);
    if (index == -1) {
      _mostrarMensaje('NO ENCONTRADO EN LA LISTA', isError: true);
      return;
    }

    final targetIndex = index + 1; // El índice 0 es el panel de control superior
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.15,
      );
      _mostrarMensaje('ENFOCANDO...', isError: false);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: targetIndex,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            alignment: 0.15,
          );
          _mostrarMensaje('ENFOCANDO...', isError: false);
        }
      });
    }
  }

  Future<void> _abrirEnFB(String url) async {
    if (url.isEmpty || url == 'undefined') {
      _mostrarMensaje('ENLACE DAÑADO', isError: true);
      return;
    }
    _marcarActual(url);
    _vibrar(durationMs: 30);

    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (err) {
        _mostrarMensaje('NO SE PUDO ABRIR ENLACE', isError: true);
      }
    }
  }

  void _toggleCalificacion(int globalIndex, String estado) {
    _vibrar(
      durationMs: estado == 'good' ? 15 : (estado == 'regular' ? 20 : 40),
    );
    setState(() {
      if (_grupos[globalIndex].status == estado) {
        _grupos[globalIndex].status = 'none';
      } else {
        _grupos[globalIndex].status = estado;
      }
    });
    _guardarDatos();
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
        return Dialog(
          backgroundColor: CyberTheme.surface,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: CyberTheme.warning, width: 3),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ALEATORIZAR GRUPOS',
                  style: CyberTheme.mono(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: CyberTheme.warning,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Esta acción reorganizará todos los enlaces al azar y cambiará el orden de las cuentas de 25.\n\n¿Deseas continuar?',
                  style: CyberTheme.mono(
                    fontSize: 13,
                    color: CyberTheme.textMuted,
                  ),
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
            ),
          ),
        );
      },
    );
  }

  void _aleatorizarGrupos() {
    _vibrar(durationMs: 40);
    if (_grupos.length <= 1) return;
    setState(() {
      _grupos.shuffle(Random());
    });
    _guardarDatos();
    _mostrarMensaje('GRUPOS ALEATORIZADOS', isError: false);
  }

  // ----------------------------------------------------
  // IMPORT / EXPORT / SHARE
  // ----------------------------------------------------
  Future<void> _compartirJSON() async {
    _vibrar(durationMs: 30);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(
      _grupos.map((g) => g.toJson()).toList(),
    );
    await SharePlus.instance.share(
      ShareParams(
        text: jsonStr,
        subject: 'cyber_grupos.json',
      ),
    );
  }

  Future<void> _exportarJSON() async {
    _vibrar(durationMs: 25);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(
      _grupos.map((g) => g.toJson()).toList(),
    );
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
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (files.isEmpty) return;

      final file = files.first;
      final rawContent = await file.xFile.readAsString();
      _cargarDesdeStringJSON(rawContent);
    } catch (e) {
      _mostrarMensaje('ARCHIVO NO VÁLIDO', isError: true);
    }
  }

  void _cargarDesdeStringJSON(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is List) {
        _vibrar(durationMs: 30);
        final resultado = FBUrlHelper.sanearGrupos(decoded);
        setState(() {
          _grupos = resultado.items;
        });
        _guardarDatos();
        _mostrarMensaje(
          resultado.huboCambios
              ? 'BASE DE DATOS CARGADA Y SANEADA'
              : 'BASE DE DATOS CARGADA',
          isError: false,
        );
      } else {
        _mostrarMensaje('FORMATO NO VÁLIDO', isError: true);
      }
    } catch (e) {
      _mostrarMensaje('ERROR EN EL FORMATO', isError: true);
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
        return Dialog(
          backgroundColor: CyberTheme.surface,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: CyberTheme.error, width: 3),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ELIMINAR GRUPO',
                  style: CyberTheme.mono(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: CyberTheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Esta acción no se puede deshacer.',
                  style: CyberTheme.mono(
                    fontSize: 13,
                    color: CyberTheme.textMuted,
                  ),
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
                        setState(() {
                          if (_grupos[globalIndex].url == _urlActual) {
                            _urlActual = '';
                          }
                          _grupos.removeAt(globalIndex);
                        });
                        _guardarDatos();
                        _mostrarMensaje('ELIMINADO', isError: false);
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
            ),
          ),
        );
      },
    );
  }

  void _abrirModalReemplazar(int globalIndex) {
    _vibrar(durationMs: 20);
    final editController = TextEditingController(
      text: _grupos[globalIndex].url,
    );

    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return Dialog(
          backgroundColor: CyberTheme.surface,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: CyberTheme.primary, width: 3),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REEMPLAZAR GRUPO',
                  style: CyberTheme.mono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CyberTheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
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

                        Navigator.of(ctx).pop();
                        _vibrar(durationMs: 25);
                        setState(() {
                          if (_grupos[globalIndex].url == _urlActual) {
                            _urlActual = link;
                          }
                          _grupos[globalIndex] = GroupItem(
                            url: link,
                            status: 'none',
                          );
                        });
                        _guardarDatos();
                        _mostrarMensaje('REEMPLAZADO', isError: false);
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
            ),
          ),
        );
      },
    );
  }

  void _abrirModalTexto() {
    _vibrar(durationMs: 20);
    final textController = TextEditingController(
      text: jsonEncode(_grupos.map((g) => g.toJson()).toList()),
    );

    showDialog(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) {
        return Dialog(
          backgroundColor: CyberTheme.surface,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: CyberTheme.primary, width: 3),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESPALDO EN TEXTO',
                  style: CyberTheme.mono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CyberTheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          label: 'Restaurar',
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _cargarDesdeStringJSON(textController.text);
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
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------
  // BUILD
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final total = _grupos.length;
    final totalCuentas = total == 0 ? 1 : ((total + 24) ~/ 25);

    return Scaffold(
      body: SafeArea(
        child: ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 80),
          itemCount: total == 0 ? 2 : 1 + total,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildTopControlPanel(total, totalCuentas);
            }

            if (total == 0) {
              return _buildCuentaCard(
                cuentaNumero: 1,
                startIdx: 0,
                chunk: const [],
              );
            }

            final globalIdx = index - 1;
            final item = _grupos[globalIdx];
            final localNum = (globalIdx % 25) + 1;
            final cuentaNumero = (globalIdx ~/ 25) + 1;
            final isFirstInCuenta = (globalIdx % 25) == 0;
            final isLastInCuenta =
                ((globalIdx % 25) == 24) || (globalIdx == total - 1);

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
          'TOTAL: $total GRUPOS • CUENTAS: $totalCuentas',
          textAlign: TextAlign.center,
          style: CyberTheme.mono(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: CyberTheme.textMuted,
          ),
        ),
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
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: CyberTheme.bg,
                        border: Border.all(color: CyberTheme.border, width: 2),
                      ),
                      child: TextField(
                        controller: _urlController,
                        style: CyberTheme.mono(fontSize: 13),
                        onSubmitted: (_) => _agregarGrupo(),
                        decoration: const InputDecoration(
                          hintText: 'PEGA EL ENLACE AQUÍ...',
                          hintStyle: TextStyle(
                            fontFamily: 'monospace',
                            color: CyberTheme.textMuted,
                            fontSize: 12,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
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

              // Mensaje de estado dinámico
              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _statusIsError
                        ? CyberTheme.redActiveBg
                        : CyberTheme.greenActiveBg,
                    border: Border.all(
                      color: _statusIsError
                          ? CyberTheme.error
                          : CyberTheme.secondary,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: CyberTheme.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _statusIsError
                          ? CyberTheme.error
                          : CyberTheme.secondary,
                    ),
                  ),
                ),
              ],

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
                    label: 'Aleatorizar',
                    onPressed: _confirmarAleatorizarGrupos,
                    backgroundColor: CyberTheme.bg,
                    textColor: CyberTheme.primary,
                    borderColor: CyberTheme.primary,
                  ),
                  RetroButton(
                    label: 'Compartir',
                    onPressed: _compartirJSON,
                    backgroundColor: CyberTheme.surfaceVariant,
                    textColor: CyberTheme.text,
                  ),
                  RetroButton(
                    label: 'Guardar',
                    onPressed: _exportarJSON,
                    backgroundColor: CyberTheme.surfaceVariant,
                    textColor: CyberTheme.text,
                  ),
                  RetroButton(
                    label: 'Cargar',
                    onPressed: _importarJSON,
                    backgroundColor: CyberTheme.surfaceVariant,
                    textColor: CyberTheme.text,
                  ),
                  RetroButton(
                    label: 'Texto',
                    onPressed: _abrirModalTexto,
                    backgroundColor: CyberTheme.surfaceVariant,
                    textColor: CyberTheme.text,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // RADAR DE MISIÓN (ESTILO 8-BITS)
  // ==========================================
  Widget _buildMissionRadar(int totalGrupos) {
    if (_agregadosSesion > 25) {
      return const SizedBox.shrink();
    }

    if (_agregadosSesion == 25) {
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

    int faltan = 25 - (totalGrupos % 25);
    if (faltan == 25 && totalGrupos > 0) faltan = 0;

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
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
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
                  const TextSpan(text: '/25 AÑADIDOS HOY'),
                ],
              ),
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
                'LAS CUENTAS ESTÁN LLENAS (MÚLTIPLO DE 25)',
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
  Widget _buildCuentaCard({
    required int cuentaNumero,
    required int startIdx,
    required List<GroupItem> chunk,
  }) {
    final bool isFull = chunk.length == 25;

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
          // Header de la cuenta
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
                  'CUENTA $cuentaNumero',
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
                    color: isFull ? CyberTheme.greenActiveBg : CyberTheme.bg,
                    border: Border.all(
                      color: isFull ? CyberTheme.secondary : CyberTheme.border,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    '${chunk.length}/25',
                    style: CyberTheme.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isFull ? CyberTheme.secondary : CyberTheme.text,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Elementos de la lista de esta cuenta
          if (chunk.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'SIN GRUPOS EN ESTA CUENTA',
                textAlign: TextAlign.center,
                style: CyberTheme.mono(
                  fontSize: 11,
                  color: CyberTheme.textMuted,
                ),
              ),
            )
          else
            ...List.generate(chunk.length, (localIdx) {
              final globalIdx = startIdx + localIdx;
              final item = chunk[localIdx];
              final isLast = localIdx == chunk.length - 1;
              return _buildGroupRow(item, localIdx + 1, globalIdx, isLast);
            }),
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
    final startIdx = (cuentaNumero - 1) * 25;
    final endIdx = min(startIdx + 25, total);
    final cuentaLength = endIdx - startIdx;
    final isFull = cuentaLength == 25;

    Widget? accountHeader;
    if (isFirstInCuenta) {
      accountHeader = Container(
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
            Text(
              'CUENTA $cuentaNumero',
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
                color: isFull ? CyberTheme.greenActiveBg : CyberTheme.bg,
                border: Border.all(
                  color: isFull ? CyberTheme.secondary : CyberTheme.border,
                  width: 2,
                ),
              ),
              child: Text(
                '$cuentaLength/25',
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
      children: [
        ?accountHeader,
        rowContainer,
      ],
    );
  }

  Widget _buildGroupRow(
    GroupItem item,
    int localNum,
    int globalIdx,
    bool isLast,
  ) {
    final bool isCurrent = item.url.isNotEmpty && item.url == _urlActual;

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
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
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
    final shadowOffset =
        _isPressed ? const Offset(0.5, 0.5) : const Offset(2, 2);

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
    final shadowOffset =
        _isPressed ? const Offset(1, 1) : const Offset(3, 3);

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
