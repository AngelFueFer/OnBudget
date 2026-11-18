import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:presupuesto_familiar/constants/api_config.dart';
import 'package:presupuesto_familiar/servicios/config_mercados.dart';
import 'package:presupuesto_familiar/utilidades/isin.dart';

class ApiBolsaException implements Exception {
  final String codigo;
  final String mensaje;
  final String? detalles;

  ApiBolsaException({
    required this.codigo,
    required this.mensaje,
    this.detalles,
  });

  @override
  String toString() => 'ApiBolsaException($codigo): $mensaje${detalles != null ? ' - $detalles' : ''}';
}

class ApiBolsa {
  // Convierte un ISIN en un ticker de EODHD ('CODIGO.BOLSA'), o null si no se encuentra.
  static Future<String?> buscarTickerPorIsin(String isin) async {
    if (!ConfigMercados.conectada) return null; // Conexión desactivada o sin clave
    try {
      final url = Uri.parse('${ApiConfig.urlBusqueda}/$isin?api_token=${ConfigMercados.clave}&fmt=json');
      final respuesta = await http.get(url).timeout(Duration(seconds: ApiConfig.timeoutSegundos));
      if (respuesta.statusCode != 200) return null;

      final resultados = json.decode(respuesta.body);
      if (resultados is! List || resultados.isEmpty) return null;
      // Preferimos el resultado cuyo ISIN coincide exactamente
      final elegido = resultados.cast<Map<String, dynamic>>().firstWhere(
            (r) => (r['ISIN'] ?? '').toString().toUpperCase() == isin.toUpperCase(),
            orElse: () => resultados.first as Map<String, dynamic>,
          );
      final codigo = elegido['Code'];
      final bolsa = elegido['Exchange'];
      if (codigo == null || bolsa == null) return null;
      _logInfo('ISIN $isin -> $codigo.$bolsa');
      return '$codigo.$bolsa';
    } catch (e) {
      _logError('No se pudo resolver el ISIN $isin', e);
      return null;
    }
  }

  // Comprueba la clave del usuario pidiendo una cotización conocida
  static Future<bool> probarConexion() async {
    if (!ConfigMercados.tieneClave) return false;
    try {
      return await _obtenerPrecioConTimeout('AAPL.US') != null;
    } catch (_) {
      return false;
    }
  }

  static Future<double?> obtenerPrecioActual(String ticker) async {
    // Un ISIN sin resolver no es un ticker válido: no gastamos llamadas (ni reintentos) en él
    if (!ConfigMercados.conectada || Isin.pareceIsin(ticker)) return null;
    int intentosRestantes = ApiConfig.maxReintentos;

    while (intentosRestantes > 0) {
      try {
        final precio = await _obtenerPrecioConTimeout(ticker);
        return precio;
      } on ApiBolsaException catch (e) {
        intentosRestantes--;

        if (intentosRestantes > 0) {
          _logWarning('Reintentando ($intentosRestantes) para $ticker: ${e.mensaje}');
          await Future.delayed(
            Duration(milliseconds: ApiConfig.delayReintentoMs),
          );
        } else {
          _logError('Agotados reintentos para $ticker', e);
          return null;
        }
      } catch (e) {
        _logError('Error desconocido para $ticker', e);
        return null;
      }
    }
    return null;
  }

  static Future<double?> _obtenerPrecioConTimeout(String ticker) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/$ticker?api_token=${ConfigMercados.clave}&fmt=json',
      );

      final respuesta = await http.get(url).timeout(
        Duration(seconds: ApiConfig.timeoutSegundos),
        onTimeout: () {
          throw ApiBolsaException(
            codigo: ApiErrorCode.timeout,
            mensaje: 'Tiempo de espera agotado',
            detalles: 'No se recibió respuesta en ${ApiConfig.timeoutSegundos}s',
          );
        },
      );

      return _procesarRespuesta(respuesta, ticker);
    } on SocketException catch (e) {
      throw ApiBolsaException(
        codigo: ApiErrorCode.noConexion,
        mensaje: 'Error de conexión de red',
        detalles: e.message,
      );
    } on TimeoutException catch (_) {
      throw ApiBolsaException(
        codigo: ApiErrorCode.timeout,
        mensaje: 'Tiempo de espera agotado',
        detalles: 'Conexión perdida después de ${ApiConfig.timeoutSegundos}s',
      );
    } on FormatException catch (e) {
      throw ApiBolsaException(
        codigo: ApiErrorCode.parseo,
        mensaje: 'Error al parsear respuesta JSON',
        detalles: e.message,
      );
    }
  }

  static double? _procesarRespuesta(http.Response respuesta, String ticker) {
    if (respuesta.statusCode == 200) {
      try {
        final datos = json.decode(respuesta.body) as Map<String, dynamic>;

        if (datos['close'] == null) {
          throw ApiBolsaException(
            codigo: ApiErrorCode.datosFaltantes,
            mensaje: 'Campo "close" no encontrado en respuesta',
            detalles: 'Respuesta: ${respuesta.body}',
          );
        }

        if (datos['close'] == 'NA') {
          throw ApiBolsaException(
            codigo: ApiErrorCode.mercadoCerrado,
            mensaje: 'Mercado cerrado o dato no disponible',
            detalles: 'El ticker $ticker retornó "NA"',
          );
        }

        final precio = double.tryParse(datos['close'].toString());
        if (precio == null) {
          throw ApiBolsaException(
            codigo: ApiErrorCode.parseo,
            mensaje: 'No se pudo convertir precio a double',
            detalles: 'Valor: ${datos['close']}',
          );
        }

        _logInfo('Precio obtenido para $ticker: $precio€');
        return precio;
      } catch (e) {
        if (e is ApiBolsaException) rethrow;
        throw ApiBolsaException(
          codigo: ApiErrorCode.parseo,
          mensaje: 'Error procesando respuesta',
          detalles: e.toString(),
        );
      }
    } else {
      throw ApiBolsaException(
        codigo: ApiErrorCode.statusCode,
        mensaje: 'Servidor retornó código ${respuesta.statusCode}',
        detalles: respuesta.body,
      );
    }
  }

  // Logging helpers
  static void _logInfo(String mensaje) {
    debugPrint('[ApiBolsa-INFO] $mensaje');
  }

  static void _logWarning(String mensaje) {
    debugPrint('[ApiBolsa-WARN] $mensaje');
  }

  static void _logError(String mensaje, dynamic error) {
    debugPrint('[ApiBolsa-ERROR] $mensaje');
    debugPrint('[ApiBolsa-ERROR] Detalles: $error');
  }
}
