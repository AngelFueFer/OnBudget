import 'dart:async';
import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';

// Enable Banking (enablebanking.com): agregador con licencia AISP en la UE.
// Cada usuario registra una aplicación de PRODUCCIÓN en su panel de control y la activa enlazando
// sus propias cuentas ("modo restringido", gratuito para uso personal no comercial).
// Autenticación: JWT RS256 firmado con la clave privada de la aplicación (kid = id de la aplicación).
// Referencia: https://enablebanking.com/docs/api/reference/
class EnableBanking implements ProveedorBancario {
  static const String urlBase = 'https://api.enablebanking.com';
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _vidaToken = Duration(hours: 1); // El máximo que admite la API es 24 h
  static const int _maxPaginas = 50; // Tope de páginas de movimientos por consulta

  final String idAplicacion;
  final String clavePrivadaPem;
  final http.Client _cliente;
  // Firma del JWT. Se puede sustituir en los tests para no necesitar una clave real.
  final String Function()? firmarToken;

  String? _token;
  DateTime? _tokenCaduca;

  EnableBanking({required this.idAplicacion, required this.clavePrivadaPem, http.Client? cliente, this.firmarToken})
      : _cliente = cliente ?? http.Client();

  @override
  TipoProveedor get tipo => TipoProveedor.enableBanking;

  String _tokenVigente() {
    final ahora = DateTime.now();
    if (_token != null && _tokenCaduca != null && ahora.isBefore(_tokenCaduca!)) return _token!;
    final firmar = firmarToken;
    final token = firmar != null ? firmar() : _firmar();
    _token = token;
    _tokenCaduca = ahora.add(_vidaToken - const Duration(minutes: 5));
    return token;
  }

  String _firmar() {
    try {
      final jwt = JWT(
        {'iss': 'enablebanking.com', 'aud': 'api.enablebanking.com'},
        header: {'kid': idAplicacion},
      );
      return jwt.sign(RSAPrivateKey(clavePrivadaPem), algorithm: JWTAlgorithm.RS256, expiresIn: _vidaToken);
    } catch (e) {
      throw ErrorBancario('Clave privada no válida: $e');
    }
  }

  Map<String, String> get _cabeceras => {
        'Authorization': 'Bearer ${_tokenVigente()}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> _get(String ruta, [Map<String, String>? parametros]) async {
    final uri = Uri.parse('$urlBase$ruta').replace(queryParameters: parametros);
    return _respuesta(() => _cliente.get(uri, headers: _cabeceras));
  }

  Future<Map<String, dynamic>> _post(String ruta, Map<String, dynamic> cuerpo) async {
    final uri = Uri.parse('$urlBase$ruta');
    return _respuesta(() => _cliente.post(uri, headers: _cabeceras, body: jsonEncode(cuerpo)));
  }

  Future<Map<String, dynamic>> _respuesta(Future<http.Response> Function() peticion) async {
    http.Response r;
    try {
      r = await peticion().timeout(_timeout);
    } on TimeoutException {
      throw const ErrorBancario('Tiempo de espera agotado');
    } on ErrorBancario {
      rethrow;
    } catch (e) {
      throw ErrorBancario('Sin conexión: $e');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ErrorBancario(_mensajeError(r.body), codigoHttp: r.statusCode, codigo: _codigoError(r.body));
    }
    if (r.bodyBytes.isEmpty) return {};
    try {
      final datos = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      return datos is Map<String, dynamic> ? datos : {};
    } on FormatException {
      // Un proxy o un portal cautivo puede devolver HTML con 200
      throw const ErrorBancario('Respuesta no válida del agregador');
    }
  }

  // Lee una respuesta con la forma esperada; si el agregador cambia el formato, error bancario legible
  static T _leer<T>(String que, T Function() lectura) {
    try {
      return lectura();
    } on ErrorBancario {
      rethrow;
    } catch (_) {
      throw ErrorBancario('Respuesta inesperada del agregador ($que)');
    }
  }

  // Código de error de la API (ej. 'EXPIRED_SESSION'), si lo trae
  static String? _codigoError(String cuerpo) {
    try {
      final datos = jsonDecode(cuerpo);
      if (datos is Map && datos['error'] is String) return datos['error'] as String;
    } catch (_) {}
    return null;
  }

  static String _mensajeError(String cuerpo) {
    try {
      final datos = jsonDecode(cuerpo);
      if (datos is Map) return [datos['error'], datos['message'], datos['detail']].whereType<Object>().join(': ');
    } catch (_) {}
    return cuerpo.length > 200 ? cuerpo.substring(0, 200) : cuerpo;
  }

  @override
  Future<bool> probarConexion() async {
    try {
      await _get('/aspsps', {'country': 'ES'});
      return true;
    } on ErrorBancario {
      return false;
    }
  }

  @override
  Future<List<BancoDisponible>> bancos(String pais) async {
    final datos = await _get('/aspsps', {'country': pais, 'psu_type': 'personal', 'service': 'AIS'});
    final lista = (datos['aspsps'] as List?) ?? const [];
    return lista
        .whereType<Map<String, dynamic>>()
        .where((a) => a['name'] is String && (a['name'] as String).isNotEmpty)
        .map((a) {
      final segundos = (a['maximum_consent_validity'] as num?)?.toInt();
      return BancoDisponible(
        nombre: a['name'] as String,
        pais: (a['country'] as String?) ?? pais,
        logo: a['logo'] as String?,
        diasConsentimientoMax: segundos == null ? 90 : (segundos / 86400).floor().clamp(1, 730),
      );
    }).toList()
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  @override
  Future<String> iniciarAutorizacion({
    required BancoDisponible banco,
    required String urlVuelta,
    required String estado,
    required DateTime validaHasta,
  }) async {
    final datos = await _post('/auth', {
      'access': {'valid_until': fechaHoraApi(validaHasta)},
      'aspsp': {'name': banco.nombre, 'country': banco.pais},
      'state': estado,
      'redirect_url': urlVuelta,
      'psu_type': 'personal',
    });
    final url = datos['url'];
    if (url is! String || url.isEmpty) throw const ErrorBancario('El agregador no devolvió la URL del banco');
    return url;
  }

  @override
  Future<SesionBancaria> completarAutorizacion(String codigo) async {
    final datos = await _post('/sessions', {'code': codigo});
    final sesion = _leer('sesión', () => _sesionDesdeJson(datos));
    if (sesion.cuentas.isEmpty) throw const ErrorBancario('El banco no ha autorizado ninguna cuenta');
    return sesion;
  }

  static SesionBancaria _sesionDesdeJson(Map<String, dynamic> datos) {
    final List<dynamic> cuentas = datos['accounts'] ?? [];
    return SesionBancaria(
      id: datos['session_id'] as String,
      banco: (datos['aspsp'] as Map?)?['name'] as String? ?? '',
      validaHasta: DateTime.tryParse((datos['access'] as Map?)?['valid_until'] as String? ?? ''),
      cuentas: cuentas.map((c) {
        // Versiones antiguas de la API devolvían solo el uid
        if (c is String) return CuentaRemota(uid: c);
        final mapa = c as Map<String, dynamic>;
        return CuentaRemota(
          uid: mapa['uid'] as String,
          iban: (mapa['account_id'] as Map?)?['iban'] as String?,
          nombre: (mapa['name'] ?? mapa['product']) as String?,
          moneda: mapa['currency'] as String?,
        );
      }).toList(),
    );
  }

  // Preferencia de tipos de saldo: contable al cierre, contable del día, disponible…
  static const List<String> _tiposSaldo = ['CLBD', 'ITBD', 'ITAV', 'CLAV', 'XPCD', 'OPBD'];

  @override
  Future<SaldoRemoto?> saldo(String cuentaUid) async {
    final datos = await _get('/accounts/$cuentaUid/balances');
    final saldos = ((datos['balances'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .where((s) => double.tryParse('${(s['balance_amount'] as Map?)?['amount']}') != null)
        .toList();
    if (saldos.isEmpty) return null;
    saldos.sort((a, b) => _prioridad(a['balance_type']).compareTo(_prioridad(b['balance_type'])));
    final elegido = saldos.first;
    final importe = double.tryParse('${(elegido['balance_amount'] as Map?)?['amount']}');
    if (importe == null) return null;
    final fecha = DateTime.tryParse('${elegido['reference_date'] ?? elegido['last_change_date_time'] ?? ''}');
    return SaldoRemoto(importe, fecha);
  }

  static int _prioridad(Object? tipo) {
    final i = _tiposSaldo.indexOf('$tipo');
    return i < 0 ? _tiposSaldo.length : i;
  }

  @override
  Future<List<MovimientoExtracto>> movimientos(String cuentaUid, {required DateTime desde}) async {
    final resultado = <MovimientoExtracto>[];
    final referencias = <String>{}; // Algunos bancos repiten movimientos entre páginas
    final claves = <String>{};
    String? continuacion;
    var paginas = 0;
    do {
      final datos = await _get('/accounts/$cuentaUid/transactions', {
        'date_from': _fecha(desde),
        'continuation_key': ?continuacion,
      });
      for (final t in ((datos['transactions'] as List?) ?? []).whereType<Map<String, dynamic>>()) {
        final referencia = t['entry_reference'];
        if (referencia is String && referencia.isNotEmpty && !referencias.add(referencia)) continue;
        final movimiento = movimientoDesdeJson(t);
        if (movimiento != null) resultado.add(movimiento);
      }
      final siguiente = datos['continuation_key'];
      // Si el banco devuelve otra vez una clave ya usada, se para para no entrar en bucle
      continuacion = siguiente is String && siguiente.isNotEmpty && claves.add(siguiente) ? siguiente : null;
      paginas++;
    } while (continuacion != null && paginas < _maxPaginas);
    resultado.sort((a, b) => a.fecha.compareTo(b.fecha));
    return resultado;
  }

  // Estados que no son un movimiento contabilizado: pendientes, retenidos, programados, anulados o rechazados
  static const Set<String> _estadosIgnorados = {'PDNG', 'HOLD', 'SCHD', 'CNCL', 'RJCT'};

  // Convierte un movimiento de la API. Solo cuentan los contabilizados: el resto puede cambiar o anularse.
  static MovimientoExtracto? movimientoDesdeJson(Map<String, dynamic> t) {
    if (_estadosIgnorados.contains(t['status'])) return null;
    final cantidad = double.tryParse('${(t['transaction_amount'] as Map?)?['amount']}');
    final fecha = DateTime.tryParse('${t['booking_date'] ?? t['value_date'] ?? t['transaction_date'] ?? ''}');
    if (cantidad == null || fecha == null) return null;
    final esCargo = t['credit_debit_indicator'] == 'DBIT' || (t['credit_debit_indicator'] == null && cantidad < 0);
    final importe = esCargo ? -cantidad.abs() : cantidad.abs();

    // Concepto: contraparte + información de la remesa, sin repetir textos
    final contraparte = ((esCargo ? t['creditor'] : t['debtor']) as Map?)?['name'];
    final remesa = switch (t['remittance_information']) {
      final List<dynamic> lista => lista.whereType<String>(),
      final String texto => [texto],
      _ => const <String>[],
    };
    final nota = t['note'];
    final candidatos = [if (contraparte is String) contraparte, ...remesa, if (nota is String) nota].map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final partes = <String>[];
    for (var i = 0; i < candidatos.length; i++) {
      final texto = candidatos[i].toLowerCase();
      // Se omite si ya aparece entero en otro texto (o es un repetido anterior)
      final incluido = [
        for (var j = 0; j < candidatos.length; j++)
          if (j != i) candidatos[j].toLowerCase(),
      ].any((otro) => otro.contains(texto) && (otro != texto || partes.any((p) => p.toLowerCase() == texto)));
      if (!incluido) partes.add(candidatos[i]);
    }
    return MovimientoExtracto(
      fecha: DateTime(fecha.year, fecha.month, fecha.day),
      concepto: partes.join(' '),
      importe: importe,
    );
  }

  // Fecha y hora en UTC sin fracciones de segundo ('2027-05-16T21:20:40Z'): la forma que admite cualquier validador
  static String fechaHoraApi(DateTime f) {
    final utc = f.toUtc();
    return '${_fecha(utc)}T${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  static String _fecha(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

  @override
  Future<void> cerrarSesion(String sesionId) async {
    try {
      await _respuesta(() => _cliente.delete(Uri.parse('$urlBase/sessions/$sesionId'), headers: _cabeceras));
    } on ErrorBancario {
      // Si no se puede revocar, el consentimiento caduca solo
    }
  }
}
