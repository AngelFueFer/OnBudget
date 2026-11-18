import 'package:presupuesto_familiar/modelos/extracto.dart';

// Conexión con los bancos por Open Banking (PSD2).
//
// La app no habla directamente con cada banco: lo hace a través de un agregador con licencia
// de proveedor de información sobre cuentas (AISP). Cada agregador se implementa como un
// ProveedorBancario; el usuario elige cuál usar en Configuración > Conexión con los bancos.
//
// Flujo:
//  1. bancos(pais)                  -> lista de bancos que el agregador puede conectar
//  2. iniciarAutorizacion(...)      -> URL del banco donde el usuario da su consentimiento
//  3. el banco redirige a la URL de vuelta con ?code=...
//  4. completarAutorizacion(code)   -> sesión con las cuentas autorizadas
//  5. saldo(...) / movimientos(...) -> datos de cada cuenta mientras el consentimiento esté vigente

enum TipoProveedor { enableBanking }

// Banco que ofrece el agregador
class BancoDisponible {
  final String nombre; // Nombre exacto que espera el agregador
  final String pais; // ISO 3166 (ES, PT, FR…)
  final String? logo; // URL del logo
  final int diasConsentimientoMax; // Validez máxima del consentimiento que admite el banco

  const BancoDisponible({required this.nombre, required this.pais, this.logo, this.diasConsentimientoMax = 90});
}

// Cuenta autorizada por el usuario en el banco
class CuentaRemota {
  final String uid; // Identificador de la cuenta en el agregador
  final String? iban;
  final String? nombre;
  final String? moneda;

  const CuentaRemota({required this.uid, this.iban, this.nombre, this.moneda});
}

// Resultado de completar la autorización
class SesionBancaria {
  final String id;
  final String banco;
  final DateTime? validaHasta; // Cuándo caduca el consentimiento (luego hay que volver a conectar)
  final List<CuentaRemota> cuentas;

  const SesionBancaria({required this.id, required this.banco, required this.cuentas, this.validaHasta});
}

class SaldoRemoto {
  final double importe;
  final DateTime? fecha;
  const SaldoRemoto(this.importe, this.fecha);
}

// Error del agregador o del banco, con un motivo legible para el registro
class ErrorBancario implements Exception {
  final String motivo;
  final int? codigoHttp;
  final String? codigo; // Código de error del agregador (ej. 'EXPIRED_SESSION'), si lo da

  const ErrorBancario(this.motivo, {this.codigoHttp, this.codigo});

  // Códigos documentados por Enable Banking (FAQ de la API)
  static const String codigoSesionCaducada = 'EXPIRED_SESSION';
  static const String codigoPeriodoNoValido = 'WRONG_TRANSACTIONS_PERIOD';

  // El consentimiento caducó o se revocó: hay que volver a conectar la cuenta.
  // Un 401 de credenciales de la aplicación (JWT) también entra aquí: reconectar no lo arregla, pero
  // la pantalla de conexión permite revisar las credenciales en el mismo sitio.
  bool get requiereReconectar =>
      codigoHttp == 401 || codigoHttp == 403 || codigo == codigoSesionCaducada;

  // El banco limita las consultas sin el usuario delante (PSD2: unas 4 al día por cuenta)
  bool get limiteConsultas => codigoHttp == 429 || (codigo?.contains('RATE_LIMIT') ?? false);

  @override
  String toString() => 'ErrorBancario($codigoHttp): $motivo';
}

abstract class ProveedorBancario {
  TipoProveedor get tipo;

  // Comprueba que las credenciales del usuario son válidas
  Future<bool> probarConexion();

  Future<List<BancoDisponible>> bancos(String pais);

  // Devuelve la URL a la que hay que mandar al usuario para que autorice el acceso en su banco
  Future<String> iniciarAutorizacion({
    required BancoDisponible banco,
    required String urlVuelta,
    required String estado,
    required DateTime validaHasta,
  });

  Future<SesionBancaria> completarAutorizacion(String codigo);

  Future<SaldoRemoto?> saldo(String cuentaUid);

  // Movimientos contabilizados desde la fecha indicada (incluida)
  Future<List<MovimientoExtracto>> movimientos(String cuentaUid, {required DateTime desde});

  // Revoca el consentimiento en el agregador (si falla no pasa nada: caduca solo)
  Future<void> cerrarSesion(String sesionId);
}

// Saca el código de autorización de la URL de vuelta que el usuario pega
// ('https://…/banco.html?code=abc&state=xyz') o lo devuelve tal cual si ya es el código.
// Si la URL trae error (el usuario canceló en el banco) devuelve null.
String? codigoDeUrlVuelta(String texto, {String? estadoEsperado}) {
  final limpio = texto.trim();
  if (limpio.isEmpty) return null;
  final uri = Uri.tryParse(limpio);
  if (uri == null || !uri.hasScheme) return limpio.contains(' ') ? null : limpio;
  final parametros = {...uri.queryParameters, ...Uri.splitQueryString(uri.fragment)};
  if (parametros.containsKey('error')) return null;
  if (estadoEsperado != null && parametros['state'] != null && parametros['state'] != estadoEsperado) return null;
  final codigo = parametros['code'];
  return (codigo == null || codigo.isEmpty) ? null : codigo;
}
