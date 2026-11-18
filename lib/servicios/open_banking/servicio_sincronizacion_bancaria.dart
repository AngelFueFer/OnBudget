import 'dart:math';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/servicios/open_banking/config_open_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_extractos.dart';
import 'package:presupuesto_familiar/utilidades/iban.dart';

// Une las cuentas de la app con las del banco (Open Banking) y descarga saldo y movimientos.
// Los movimientos descargados se tratan igual que un extracto: pasan por la pantalla de
// importación, que sugiere categoría y descarta los que ya están en el presupuesto.
class ServicioSincronizacionBancaria {
  static const int diasPrimeraDescarga = 90; // Muchos bancos solo dan 90 días sin volver a pedir SCA
  static const int diasSolape = 7; // Se repiten unos días por si el banco contabiliza tarde (los duplicados se descartan)
  // Un gasto apuntado por notificación y el mismo cargo del banco pueden diferir en fecha y concepto
  static const int diasMargenDuplicados = 3;
  static const int diasConsentimiento = 180;
  static const List<int> diasReintentoPeriodo = [30, 7]; // Historial más corto si el banco rechaza el pedido // Máximo PSD2 para datos de cuenta; se recorta al que admita el banco

  static ProveedorBancario proveedor() => ConfigOpenBanking.crear();

  // Valor aleatorio que viaja al banco y vuelve en la URL de vuelta (protege contra respuestas cruzadas)
  static String nuevoEstado() {
    final aleatorio = Random.secure();
    return List.generate(16, (_) => aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // Bancos del agregador, con los que se parecen al de la cuenta primero
  static List<BancoDisponible> ordenarPara(List<BancoDisponible> bancos, CuentaBancaria cuenta) {
    final catalogo = cuenta.bancoCatalogo;
    final nombres = [
      if (cuenta.banco.isNotEmpty) cuenta.banco,
      if (catalogo != null) ...[catalogo.nombre, ...catalogo.alias],
    ].map(_simplificar).where((n) => n.isNotEmpty).toList();
    bool parecido(BancoDisponible b) {
      final nombre = _simplificar(b.nombre);
      return nombres.any((n) => nombre.contains(n) || n.contains(nombre));
    }

    return [...bancos.where(parecido), ...bancos.where((b) => !parecido(b))];
  }

  // Banco del catálogo de la app que corresponde a un banco del agregador (para el avatar)
  static BancoCatalogo? bancoCatalogo(String nombre) {
    final simple = _simplificar(nombre);
    return CatalogoBancos.bancos
        .where((b) => [b.nombre, ...b.alias].any((n) => _simplificar(n) == simple))
        .firstOrNull ??
        CatalogoBancos.bancos.where((b) => simple.contains(_simplificar(b.nombre))).firstOrNull;
  }

  static DateTime validezConsentimiento(BancoDisponible banco, {DateTime? ahora}) {
    final dias = min(banco.diasConsentimientoMax, diasConsentimiento);
    return (ahora ?? DateTime.now()).add(Duration(days: dias));
  }

  // Cuenta del banco que corresponde a la de la app: por IBAN; si solo hay una, esa.
  // null si hay varias y ninguna coincide (hay que preguntar al usuario).
  static CuentaRemota? cuentaCorrespondiente(SesionBancaria sesion, CuentaBancaria cuenta) {
    final iban = cuenta.iban;
    if (iban != null) {
      final porIban = sesion.cuentas.where((c) => c.iban != null && Iban.normalizar(c.iban!) == iban).firstOrNull;
      if (porIban != null) return porIban;
    }
    return sesion.cuentas.length == 1 ? sesion.cuentas.single : null;
  }

  static Future<void> enlazar(CuentaBancaria cuenta, SesionBancaria sesion, CuentaRemota remota) async {
    await ServicioCuentasAhorro.guardarEnlace(
      cuenta.id,
      EnlaceBancario(
        proveedor: ConfigOpenBanking.proveedor.name,
        sesionId: sesion.id,
        cuentaUid: remota.uid,
        validaHasta: sesion.validaHasta,
      ),
    );
    // Si la cuenta no tenía IBAN, se completa con el del banco
    if (cuenta.iban == null && remota.iban != null && Iban.esValido(Iban.normalizar(remota.iban!))) {
      await ServicioCuentasAhorro.editar(cuenta.id, iban: remota.iban);
    }
  }

  static Future<void> desconectar(CuentaBancaria cuenta) async {
    final enlace = cuenta.enlace;
    if (enlace == null) return;
    await ServicioCuentasAhorro.guardarEnlace(cuenta.id, null);
    // Otras cuentas pueden compartir la sesión: solo se revoca si ya nadie la usa
    final otras = await ServicioCuentasAhorro.cargarTodas();
    if (otras.any((c) => c.enlace?.sesionId == enlace.sesionId)) return;
    await proveedor().cerrarSesion(enlace.sesionId);
  }

  // Saldo y movimientos nuevos de una cuenta conectada, como si fuera un extracto
  static Future<ExtractoCuenta> descargar(CuentaBancaria cuenta, {DateTime? ahora}) async {
    final enlace = cuenta.enlace;
    if (enlace == null) throw const ErrorBancario('La cuenta no está conectada');
    final hoy = ahora ?? DateTime.now();
    // Sin llamar: con el consentimiento vencido el banco respondería con un error de sesión
    if (enlace.caducado(hoy)) {
      throw const ErrorBancario('Consentimiento caducado', codigo: ErrorBancario.codigoSesionCaducada);
    }
    final ultima = enlace.ultimaSincronizacion;
    // Se resta en días de calendario: con Duration, un cambio de hora desplaza el resultado una hora
    final base = ultima ?? hoy;
    final dias = ultima == null ? diasPrimeraDescarga : diasSolape;
    final desde = DateTime(base.year, base.month, base.day - dias, base.hour, base.minute, base.second);
    final api = proveedor();
    final movimientos = await _movimientos(api, enlace.cuentaUid, desde, hoy);
    // Algunos bancos no dan saldo por PSD2: sin saldo se importan igual los movimientos
    SaldoRemoto? saldo;
    try {
      saldo = await api.saldo(enlace.cuentaUid);
    } on ErrorBancario catch (e) {
      if (e.requiereReconectar || e.limiteConsultas) rethrow;
    }
    return ExtractoCuenta(
      saldoFinal: saldo?.importe,
      fechaSaldo: saldo == null ? null : (saldo.fecha ?? hoy),
      movimientos: movimientos,
    );
  }

  // Si el banco no admite tanto historial (WRONG_TRANSACTIONS_PERIOD) se reintenta con menos días
  static Future<List<MovimientoExtracto>> _movimientos(ProveedorBancario api, String uid, DateTime desde, DateTime hoy) async {
    final alternativas = [
      desde,
      for (final dias in diasReintentoPeriodo)
        if (DateTime(hoy.year, hoy.month, hoy.day - dias).isAfter(desde)) DateTime(hoy.year, hoy.month, hoy.day - dias),
    ];
    for (var i = 0; ; i++) {
      try {
        return await api.movimientos(uid, desde: alternativas[i]);
      } on ErrorBancario catch (e) {
        if (e.codigo != ErrorBancario.codigoPeriodoNoValido || i == alternativas.length - 1) rethrow;
      }
    }
  }

  // true si no hay movimientos o todos están ya en el presupuesto (con el margen de días de la sincronización)
  static Future<bool> nadaNuevo(ExtractoCuenta extracto) async {
    if (extracto.movimientos.isEmpty) return true;
    final existentes = await ServicioExtractos.movimientosExistentes();
    final repetidos = ServicioExtractos.indicesYaImportados(extracto.movimientos, existentes, margenDias: diasMargenDuplicados);
    return repetidos.length == extracto.movimientos.length;
  }

  static Future<void> marcarSincronizada(CuentaBancaria cuenta, {DateTime? cuando}) async {
    final enlace = cuenta.enlace;
    if (enlace == null) return;
    await ServicioCuentasAhorro.guardarEnlace(cuenta.id, enlace.sincronizado(cuando ?? DateTime.now()));
  }

  static String _simplificar(String texto) {
    const conTilde = 'áàäâéèëêíìïîóòöôúùüûñç';
    const sinTilde = 'aaaaeeeeiiiioooouuuunc';
    var resultado = texto.toLowerCase().trim();
    for (var i = 0; i < conTilde.length; i++) {
      resultado = resultado.replaceAll(conTilde[i], sinTilde[i]);
    }
    return resultado.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
