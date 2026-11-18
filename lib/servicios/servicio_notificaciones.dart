import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/servicios/detector_pagos.dart';
import 'package:presupuesto_familiar/servicios/detector_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/servicio_pagos_detectados.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';

// Lectura de notificaciones (EN DESARROLLO). Solo Android.
// Solo se procesan las notificaciones de los wallets (DetectorTarjetas.wallets), de las apps
// bancarias del catálogo (CatalogoBancos.paquetesAndroid) y de las apps de pago (DetectorPagos.appsPago);
// el resto se ignora. De cada notificación solo se guarda la tarjeta detectada o el pago (importe,
// comercio), nunca el texto completo.
//
// Funciona con la app cerrada: el servicio nativo (EscuchaNotificaciones.kt) guarda las notificaciones
// de esas apps en una bandeja y la app la recoge al abrirse, al volver a primer plano y, mientras
// está abierta, cada vez que llega una notificación.
class ServicioNotificaciones {
  static bool get soportado => !kIsWeb && Platform.isAndroid;

  static const MethodChannel _canal = MethodChannel('presupuesto_familiar/notificaciones');

  // Tarjetas detectadas pendientes de aceptar; la interfaz se actualiza al cambiar
  static final ValueNotifier<List<String>> detectadas = ValueNotifier([]);

  static StreamSubscription? _suscripcion;
  static Future<void> _recogiendo = Future.value();
  static _AlVolver? _alVolver;

  // Apps cuyas notificaciones se escuchan
  static List<String> get paquetes => {
        ...DetectorTarjetas.wallets.keys,
        for (final banco in CatalogoBancos.bancos) ...banco.paquetesAndroid,
        ...DetectorPagos.appsPago.keys,
      }.toList();

  static Future<bool> tienePermiso() async {
    if (!soportado) return false;
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  // Abre los ajustes de Android; devuelve true cuando el usuario concede el acceso
  static Future<bool> pedirPermiso() async {
    if (!soportado) return false;
    try {
      return await NotificationListenerService.requestPermission();
    } catch (_) {
      return false;
    }
  }

  // Si Android limita la batería de la app, puede cortar la lectura con la app cerrada
  static Future<bool> bateriaSinRestricciones() async {
    if (!soportado) return true;
    try {
      return await _canal.invokeMethod<bool>('bateriaSinRestricciones') ?? true;
    } catch (_) {
      return true;
    }
  }

  // Muestra el diálogo del sistema para quitar la restricción (el resultado se ve al volver a la app)
  static Future<void> pedirBateriaSinRestricciones() async {
    if (!soportado) return;
    try {
      await _canal.invokeMethod('pedirBateriaSinRestricciones');
    } catch (_) {}
  }

  static Future<bool> estaActivado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(DBKeys.permisoNotificaciones) ?? false;
  }

  static Future<void> activar(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DBKeys.permisoNotificaciones, valor);
    await _configurarNativo(valor);
    if (valor) {
      await _empezarEscucha();
    } else {
      await _suscripcion?.cancel();
      _suscripcion = null;
    }
  }

  // Al arrancar la app
  static Future<void> iniciarSiActivado() async {
    detectadas.value = await ServicioTarjetas.cargarDetectadas();
    await ServicioPagosDetectados.refrescar();
    if (!soportado) return;
    final activado = await estaActivado();
    // También al desactivar: así el servicio nativo deja de guardar y vacía la bandeja
    await _configurarNativo(activado);
    if (activado && await tienePermiso()) {
      // Si Android cortó el servicio (actualización de la app, falta de memoria…) se vuelve a enlazar
      try {
        await _canal.invokeMethod('reconectar');
      } catch (_) {}
      await _empezarEscucha();
    }
  }

  // El servicio nativo solo guarda si está activado y solo de estas apps
  static Future<void> _configurarNativo(bool activo) async {
    if (!soportado) return;
    try {
      await _canal.invokeMethod('configurar', {'activo': activo, 'paquetes': paquetes});
    } catch (_) {}
  }

  static Future<void> _empezarEscucha() async {
    if (_suscripcion != null || !await tienePermiso()) return;

    // Tarjetas de las notificaciones de wallet que ya estuvieran en la bandeja antes de activar.
    // Solo tarjetas: los pagos ya llegan por la bandeja nativa y sin fecha real se duplicarían.
    try {
      for (final n in await NotificationListenerService.getActiveNotifications()) {
        await _procesarTarjeta(n.packageName, n.title, n.content);
      }
    } catch (_) {}

    await recoger();
    // Con la app abierta, cada notificación nueva ya está guardada en la bandeja nativa
    _suscripcion = NotificationListenerService.notificationsStream.listen((evento) {
      if (evento.hasRemoved != true) recoger();
    });
    _alVolver ??= _AlVolver()..registrar();
  }

  // Procesa lo que el servicio nativo guardó (también con la app cerrada). Las llamadas se encadenan
  // para que dos notificaciones seguidas no escriban a la vez las mismas preferencias.
  static Future<void> recoger() => _recogiendo = _recogiendo.then((_) => _recogerAhora()).catchError((_) {});

  static Future<void> _recogerAhora() async {
    if (!soportado) return;
    final List<dynamic> pendientes = await _canal.invokeMethod('recoger') ?? [];
    // La bandeja nativa ya se vació: un elemento raro no debe hacer perder los demás
    for (final n in pendientes.whereType<Map<dynamic, dynamic>>()) {
      try {
        final ms = n['fecha'];
        final fecha = ms is int && ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
        await procesar(n['paquete'] as String?, n['titulo'] as String?, n['texto'] as String?, fecha: fecha);
      } catch (e) {
        debugPrint('Notificación no procesada: $e');
      }
    }
  }

  // fecha: cuándo llegó la notificación (si se recoge más tarde); por defecto, ahora
  static Future<void> procesar(String? paquete, String? titulo, String? texto, {DateTime? fecha}) async {
    await _procesarTarjeta(paquete, titulo, texto);
    final pago = DetectorPagos.detectar(paquete, titulo, texto, ahora: fecha);
    if (pago != null) await ServicioPagosDetectados.anadir(pago);
  }

  static Future<void> _procesarTarjeta(String? paquete, String? titulo, String? texto) async {
    final tarjeta = DetectorTarjetas.detectar(paquete, titulo, texto);
    if (tarjeta != null && await ServicioTarjetas.anadirDetectada(tarjeta)) {
      detectadas.value = await ServicioTarjetas.cargarDetectadas();
    }
  }

  static Future<void> aceptar(String tarjeta) async {
    await ServicioTarjetas.aceptarDetectada(tarjeta);
    detectadas.value = await ServicioTarjetas.cargarDetectadas();
  }

  static Future<void> descartar(String tarjeta) async {
    await ServicioTarjetas.descartarDetectada(tarjeta);
    detectadas.value = await ServicioTarjetas.cargarDetectadas();
  }
}

// Recoge la bandeja nativa cada vez que la app vuelve a primer plano
class _AlVolver with WidgetsBindingObserver {
  void registrar() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && ServicioNotificaciones._suscripcion != null) {
      ServicioNotificaciones.recoger();
    }
  }
}
