import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/servicios/detector_pagos.dart';
import 'package:presupuesto_familiar/servicios/servicio_extractos.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';

// Pagos detectados en notificaciones bancarias. Nunca se crean movimientos solos:
// el usuario confirma (se añade como gasto) o descarta cada uno.
class ServicioPagosDetectados {
  static const int _maxPendientes = 50;
  static const int _maxGestionados = 100;

  // La interfaz se actualiza al cambiar
  static final ValueNotifier<List<PagoDetectado>> pendientes = ValueNotifier([]);

  // Guarda el gasto. Se puede sustituir en los tests.
  static Future<void> Function(Transaccion) insertar = (t) => DBHelper().insertarTransaccion(t);

  static Future<List<PagoDetectado>> cargar() => _leer(DBKeys.pagosDetectados);

  // Un dato guardado dañado no debe impedir abrir la app: se ignoran las entradas que no se entienden
  static Future<List<PagoDetectado>> _leer(String clave) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final lista = jsonDecode(prefs.getString(clave) ?? '[]');
      if (lista is! List) return [];
      final pagos = <PagoDetectado>[];
      for (final e in lista) {
        try {
          pagos.add(PagoDetectado.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }
      return pagos;
    } on FormatException {
      return [];
    }
  }

  // Pagos ya confirmados o descartados: si el banco repite la notificación no se vuelven a proponer
  static Future<void> _registrarGestionado(PagoDetectado pago) async {
    final prefs = await SharedPreferences.getInstance();
    final gestionados = [pago, ...await _leer(DBKeys.pagosGestionados)];
    final recortados = gestionados.length > _maxGestionados ? gestionados.sublist(0, _maxGestionados) : gestionados;
    await prefs.setString(DBKeys.pagosGestionados, jsonEncode(recortados.map((p) => p.toJson()).toList()));
  }

  static Future<void> _guardar(List<PagoDetectado> pagos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DBKeys.pagosDetectados, jsonEncode(pagos.map((p) => p.toJson()).toList()));
    pendientes.value = pagos;
  }

  static Future<void> refrescar() async => pendientes.value = await cargar();

  // Devuelve false si ya estaba pendiente o ya se gestionó (las apps repiten y actualizan notificaciones)
  static Future<bool> anadir(PagoDetectado pago) async {
    final pagos = await cargar();
    if (pagos.any((p) => p.clave == pago.clave || p.mismoPago(pago))) return false;
    if ((await _leer(DBKeys.pagosGestionados)).any((p) => p.clave == pago.clave || p.mismoPago(pago))) return false;
    final nuevos = [pago, ...pagos];
    await _guardar(nuevos.length > _maxPendientes ? nuevos.sublist(0, _maxPendientes) : nuevos);
    return true;
  }

  static Future<void> descartar(PagoDetectado pago) async {
    await _registrarGestionado(pago);
    await _guardar((await cargar()).where((p) => p.clave != pago.clave).toList());
  }

  // Se añade como gasto con tarjeta en la Cuenta Mensual; si hay una tarjeta guardada con
  // esos últimos 4 dígitos, se asigna a ella.
  static final Set<String> _confirmando = {};

  static Future<void> confirmar(PagoDetectado pago) async {
    // Un doble toque no debe crear el gasto dos veces
    if (!_confirmando.add(pago.clave)) return;
    try {
      if (!(await cargar()).any((p) => p.clave == pago.clave)) return;
      await _confirmar(pago);
    } finally {
      _confirmando.remove(pago.clave);
    }
  }

  static Future<void> _confirmar(PagoDetectado pago) async {
    final tarjetas = await ServicioTarjetas.cargarTarjetas();
    final tarjeta = pago.ultimos4 == null ? null : tarjetas.where((t) => t.ultimos4 == pago.ultimos4).firstOrNull;
    final categoria = ServicioExtractos.sugerirCategoria(
      MovimientoExtracto(fecha: pago.fecha, concepto: pago.comercio, importe: -pago.importe),
    );
    await insertar(Transaccion(
      montoEnCentimos: pago.centimos,
      concepto: pago.comercio,
      fecha: pago.fecha,
      categoria: categoria,
      esIngreso: false,
      tarroDestino: AppStrings.cuentaMensual,
      metodoPago: AppStrings.metodoTarjeta,
      tarjeta: tarjeta?.nombre,
    ));
    await descartar(pago);
  }
}
