import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/utilidades/iban.dart';

enum TipoCuenta { corriente, ahorro }

// Conexión de una cuenta con su banco por Open Banking (ver servicios/open_banking)
class EnlaceBancario {
  final String proveedor; // TipoProveedor.name
  final String sesionId;
  final String cuentaUid; // Id de la cuenta en el agregador
  final DateTime? validaHasta; // Caducidad del consentimiento PSD2
  final DateTime? ultimaSincronizacion;

  const EnlaceBancario({
    required this.proveedor,
    required this.sesionId,
    required this.cuentaUid,
    this.validaHasta,
    this.ultimaSincronizacion,
  });

  bool caducado([DateTime? ahora]) => validaHasta != null && (ahora ?? DateTime.now()).isAfter(validaHasta!);

  EnlaceBancario sincronizado(DateTime cuando) => EnlaceBancario(
        proveedor: proveedor,
        sesionId: sesionId,
        cuentaUid: cuentaUid,
        validaHasta: validaHasta,
        ultimaSincronizacion: cuando,
      );

  Map<String, dynamic> toJson() => {
        'proveedor': proveedor,
        'sesionId': sesionId,
        'cuentaUid': cuentaUid,
        if (validaHasta != null) 'validaHasta': validaHasta!.toIso8601String(),
        if (ultimaSincronizacion != null) 'ultimaSincronizacion': ultimaSincronizacion!.toIso8601String(),
      };

  factory EnlaceBancario.fromJson(Map<String, dynamic> json) => EnlaceBancario(
        proveedor: json['proveedor'],
        sesionId: json['sesionId'],
        cuentaUid: json['cuentaUid'],
        validaHasta: json['validaHasta'] == null ? null : DateTime.tryParse(json['validaHasta']),
        ultimaSincronizacion: json['ultimaSincronizacion'] == null ? null : DateTime.tryParse(json['ultimaSincronizacion']),
      );
}

// Una cuenta bancaria (corriente o de ahorro). Solo sirve para identificarla (banco, IBAN, saldo);
// los movimientos del presupuesto no tienen por qué estar ligados a ella.
// Entre las de ahorro, la principal recibe el ahorro automático (nómina y remanente).
class CuentaBancaria {
  final String id;
  final String nombre;
  final String banco; // Nombre del banco (del catálogo o escrito a mano)
  final bool principal;
  final double tasa; // Interés anual (TAE %)
  final TipoCuenta tipo;
  final String? iban; // Normalizado, sin espacios
  final String? bancoId; // id en CatalogoBancos; null si es otro banco
  final double? saldo; // Último saldo conocido (manual o de un extracto)
  final DateTime? saldoFecha;
  final EnlaceBancario? enlace; // null si la cuenta no está conectada con el banco

  const CuentaBancaria({
    required this.id,
    required this.nombre,
    this.banco = '',
    this.principal = false,
    this.tasa = 0,
    this.tipo = TipoCuenta.ahorro,
    this.iban,
    this.bancoId,
    this.saldo,
    this.saldoFecha,
    this.enlace,
  });

  bool get conectada => enlace != null;

  bool get esAhorro => tipo == TipoCuenta.ahorro;

  BancoCatalogo? get bancoCatalogo => CatalogoBancos.porId(bancoId);

  // 'ING · Cuenta Naranja' o solo el nombre si no hay banco
  String get nombreCompleto => banco.isEmpty ? nombre : '$banco · $nombre';

  CuentaBancaria copiar({
    String? nombre,
    String? banco,
    bool? principal,
    double? tasa,
    String? iban,
    String? bancoId,
    double? saldo,
    DateTime? saldoFecha,
    EnlaceBancario? enlace,
    bool quitarIban = false,
    bool quitarBancoId = false,
    bool quitarEnlace = false,
  }) =>
      CuentaBancaria(
        id: id,
        nombre: nombre ?? this.nombre,
        banco: banco ?? this.banco,
        principal: principal ?? this.principal,
        tasa: tasa ?? this.tasa,
        tipo: tipo,
        iban: quitarIban ? null : iban ?? this.iban,
        bancoId: quitarBancoId ? null : bancoId ?? this.bancoId,
        saldo: saldo ?? this.saldo,
        saldoFecha: saldoFecha ?? this.saldoFecha,
        enlace: quitarEnlace ? null : enlace ?? this.enlace,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'banco': banco,
        'principal': principal,
        'tasa': tasa,
        'tipo': tipo.name,
        if (iban != null) 'iban': iban,
        if (bancoId != null) 'bancoId': bancoId,
        if (saldo != null) 'saldo': saldo,
        if (saldoFecha != null) 'saldoFecha': saldoFecha!.toIso8601String(),
        if (enlace != null) 'enlace': enlace!.toJson(),
      };

  // Las cuentas guardadas antes de existir 'tipo' eran todas de ahorro
  factory CuentaBancaria.fromJson(Map<String, dynamic> json) => CuentaBancaria(
        id: json['id'],
        nombre: json['nombre'],
        banco: json['banco'] ?? '',
        principal: json['principal'] ?? false,
        tasa: (json['tasa'] as num?)?.toDouble() ?? 0,
        tipo: json['tipo'] == TipoCuenta.corriente.name ? TipoCuenta.corriente : TipoCuenta.ahorro,
        iban: json['iban'],
        bancoId: json['bancoId'],
        saldo: (json['saldo'] as num?)?.toDouble(),
        saldoFecha: json['saldoFecha'] == null ? null : DateTime.tryParse(json['saldoFecha']),
        enlace: json['enlace'] is Map<String, dynamic> ? EnlaceBancario.fromJson(json['enlace']) : null,
      );
}

// Nombre histórico: el resto de la app trabaja con cuentas de ahorro
typedef CuentaAhorro = CuentaBancaria;

// Gestión de las cuentas bancarias. Por defecto no hay ninguna:
// mientras no existan cuentas de ahorro, los movimientos de Ahorro no tienen cuenta (cuentaAhorro = null).
class ServicioCuentasAhorro {
  // Mueve los movimientos de Ahorro entre cuentas. Se puede sustituir en los tests.
  static Future<void> Function(String? desde, String? hacia) reasignarMovimientos =
      (desde, hacia) => DBHelper().reasignarCuentaAhorro(desde, hacia);

  // Solo las de ahorro (las que usa la sección Ahorro y el formulario)
  static Future<List<CuentaBancaria>> cargar() async => (await cargarTodas()).where((c) => c.esAhorro).toList();

  static Future<List<CuentaBancaria>> cargarTodas() async {
    final prefs = await SharedPreferences.getInstance();
    final List<dynamic> lista = jsonDecode(prefs.getString(DBKeys.cuentasAhorro) ?? '[]');
    return lista.map((e) => CuentaBancaria.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _guardar(List<CuentaBancaria> cuentas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DBKeys.cuentasAhorro, jsonEncode(cuentas.map((c) => c.toJson()).toList()));
  }

  static Future<CuentaBancaria?> principal() async {
    final cuentas = await cargar();
    for (final c in cuentas) {
      if (c.principal) return c;
    }
    return cuentas.isEmpty ? null : cuentas.first;
  }

  // La primera cuenta de ahorro es la principal: recibe el ahorro que ya existía y el interés configurado antes
  static Future<CuentaBancaria> anadir(
    String nombre,
    String banco, {
    TipoCuenta tipo = TipoCuenta.ahorro,
    String? iban,
    String? bancoId,
    double? saldo,
  }) async {
    final cuentas = await cargarTodas();
    final esPrimera = tipo == TipoCuenta.ahorro && !cuentas.any((c) => c.esAhorro);
    double tasa = 0;
    if (esPrimera) {
      final prefs = await SharedPreferences.getInstance();
      tasa = prefs.getDouble(DBKeys.tasaAhorro) ?? 0;
    }
    // id único aunque se creen dos cuentas en el mismo instante (el reloj puede tener poca resolución)
    var marca = DateTime.now().microsecondsSinceEpoch;
    while (cuentas.any((c) => c.id == '$marca')) {
      marca++;
    }
    final nueva = CuentaBancaria(
      id: '$marca',
      nombre: nombre.trim(),
      banco: banco.trim(),
      principal: esPrimera,
      tasa: tasa,
      tipo: tipo,
      iban: _ibanOpcional(iban),
      bancoId: bancoId,
      saldo: saldo,
      saldoFecha: saldo == null ? null : DateTime.now(),
    );
    await _guardar([...cuentas, nueva]);
    if (saldo != null) await _anadirAlHistorial(nueva.id, saldo, nueva.saldoFecha!);
    if (esPrimera) await reasignarMovimientos(null, nueva.id);
    return nueva;
  }

  // iban: '' lo borra. bancoId: '' lo borra (otro banco).
  static Future<void> editar(String id, {String? nombre, String? banco, double? tasa, String? iban, String? bancoId}) async {
    final cuentas = await cargarTodas();
    await _guardar(cuentas
        .map((c) => c.id == id
            ? c.copiar(
                nombre: nombre?.trim(),
                banco: banco?.trim(),
                tasa: tasa,
                iban: _ibanOpcional(iban),
                quitarIban: iban != null && iban.trim().isEmpty,
                bancoId: bancoId == '' ? null : bancoId,
                quitarBancoId: bancoId == '',
              )
            : c)
        .toList());
  }

  // Guarda el saldo en el historial. Solo pasa a ser el saldo actual si no hay otro más reciente
  // (importar un extracto antiguo no pisa el saldo de hoy).
  static Future<void> actualizarSaldo(String id, double saldo, {DateTime? fecha}) async {
    final cuando = fecha ?? DateTime.now();
    final cuentas = await cargarTodas();
    await _guardar(cuentas.map((c) {
      if (c.id != id) return c;
      final masReciente = c.saldoFecha != null && c.saldoFecha!.isAfter(cuando);
      return masReciente ? c : c.copiar(saldo: saldo, saldoFecha: cuando);
    }).toList());
    await _anadirAlHistorial(id, saldo, cuando);
  }

  // Evolución del saldo de una cuenta, de la fecha más antigua a la más reciente
  static Future<List<({DateTime fecha, double saldo})>> historial(String id) async {
    final todo = await _leerHistorial();
    final List<dynamic> lista = todo[id] ?? [];
    return lista
        .map((e) => (fecha: DateTime.parse(e['fecha']), saldo: (e['saldo'] as num).toDouble()))
        .toList();
  }

  // Un apunte por día: si ya hay uno ese día, se sustituye
  static Future<void> _anadirAlHistorial(String id, double saldo, DateTime fecha) async {
    final todo = await _leerHistorial();
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    final apuntes = (await historial(id)).where((a) => !_mismoDia(a.fecha, dia)).toList()
      ..add((fecha: dia, saldo: saldo))
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    final recientes = apuntes.length > _maxApuntesHistorial ? apuntes.sublist(apuntes.length - _maxApuntesHistorial) : apuntes;
    todo[id] = recientes.map((a) => {'fecha': a.fecha.toIso8601String(), 'saldo': a.saldo}).toList();
    await _escribirHistorial(todo);
  }

  static const int _maxApuntesHistorial = 730; // ~2 años con un apunte diario

  static bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static Future<Map<String, dynamic>> _leerHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    return Map<String, dynamic>.from(jsonDecode(prefs.getString(DBKeys.historialSaldos) ?? '{}'));
  }

  static Future<void> _escribirHistorial(Map<String, dynamic> todo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DBKeys.historialSaldos, jsonEncode(todo));
  }

  // Cuenta cuyo IBAN corresponde al CCC de un extracto (entidad + oficina + número de cuenta)
  static Future<CuentaBancaria?> buscarPorCcc(String entidad, String oficina, String numero) async {
    final cuentas = await cargarTodas();
    return cuentas.where((c) {
      final iban = c.iban;
      if (iban == null || iban.length != 24 || !iban.startsWith('ES')) return false;
      return iban.substring(4, 12) == '$entidad$oficina' && iban.substring(14) == numero;
    }).firstOrNull;
  }

  // Conecta (o reconecta) la cuenta con su banco; null la desconecta
  static Future<void> guardarEnlace(String id, EnlaceBancario? enlace) async {
    final cuentas = await cargarTodas();
    await _guardar(cuentas.map((c) => c.id == id ? c.copiar(enlace: enlace, quitarEnlace: enlace == null) : c).toList());
  }

  static Future<void> marcarPrincipal(String id) async {
    final cuentas = await cargarTodas();
    await _guardar(cuentas.map((c) => c.esAhorro ? c.copiar(principal: c.id == id) : c).toList());
  }

  // Si es de ahorro, sus movimientos pasan a la principal (o se quedan sin cuenta si era la última).
  // Si se borra la principal, la siguiente de ahorro pasa a serlo.
  static Future<void> eliminar(String id) async {
    final cuentas = await cargarTodas();
    final eliminada = cuentas.where((c) => c.id == id).firstOrNull;
    if (eliminada == null) return;

    final resto = cuentas.where((c) => c.id != id).toList();
    final historialCompleto = await _leerHistorial();
    if (historialCompleto.remove(id) != null) await _escribirHistorial(historialCompleto);
    if (!eliminada.esAhorro) {
      await _guardar(resto);
      return;
    }

    final ahorroRestante = resto.where((c) => c.esAhorro).toList();
    if (eliminada.principal && ahorroRestante.isNotEmpty) {
      final siguiente = ahorroRestante.first.id;
      for (var i = 0; i < resto.length; i++) {
        if (resto[i].id == siguiente) resto[i] = resto[i].copiar(principal: true);
      }
    }
    await _guardar(resto);

    final ahorro = resto.where((c) => c.esAhorro);
    final destino = ahorro.where((c) => c.principal).firstOrNull ?? ahorro.firstOrNull;
    await reasignarMovimientos(id, destino?.id);
  }

  static String? _ibanOpcional(String? iban) {
    if (iban == null) return null;
    final limpio = Iban.normalizar(iban);
    return limpio.isEmpty ? null : limpio;
  }
}
