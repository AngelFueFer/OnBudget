import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/servicios/open_banking/enable_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';

// Conexión con los bancos (Open Banking), configurable por cada usuario, igual que la de bolsa:
// - viene desactivada: sin credenciales la app no hace ninguna llamada;
// - cada usuario registra su propia aplicación en el agregador y pega aquí sus credenciales
//   (en Enable Banking es gratis para enlazar las cuentas propias).
class ConfigOpenBanking {
  static TipoProveedor proveedor = TipoProveedor.enableBanking;
  static String idAplicacion = '';
  static String clavePrivada = ''; // PEM de la clave privada RSA de la aplicación
  static String urlVuelta = ''; // Debe estar dada de alta en la aplicación del agregador
  static String pais = 'ES';

  // Se puede sustituir en los tests
  static ProveedorBancario Function()? proveedorDePrueba;

  static bool get configurada => idAplicacion.isNotEmpty && clavePrivada.isNotEmpty && urlVuelta.isNotEmpty;

  static Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    proveedor = TipoProveedor.values.where((t) => t.name == prefs.getString(DBKeys.proveedorBancario)).firstOrNull ??
        TipoProveedor.enableBanking;
    idAplicacion = prefs.getString(DBKeys.idAplicacionBancaria) ?? '';
    clavePrivada = prefs.getString(DBKeys.clavePrivadaBancaria) ?? '';
    urlVuelta = prefs.getString(DBKeys.urlVueltaBancaria) ?? '';
    pais = prefs.getString(DBKeys.paisBancario) ?? 'ES';
  }

  static Future<void> guardar({
    required TipoProveedor proveedor,
    required String idAplicacion,
    required String clavePrivada,
    required String urlVuelta,
    required String pais,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    ConfigOpenBanking.proveedor = proveedor;
    ConfigOpenBanking.idAplicacion = idAplicacion.trim();
    ConfigOpenBanking.clavePrivada = clavePrivada.trim();
    ConfigOpenBanking.urlVuelta = urlVuelta.trim();
    ConfigOpenBanking.pais = pais.trim().toUpperCase();
    await prefs.setString(DBKeys.proveedorBancario, proveedor.name);
    await prefs.setString(DBKeys.idAplicacionBancaria, ConfigOpenBanking.idAplicacion);
    await prefs.setString(DBKeys.clavePrivadaBancaria, ConfigOpenBanking.clavePrivada);
    await prefs.setString(DBKeys.urlVueltaBancaria, ConfigOpenBanking.urlVuelta);
    await prefs.setString(DBKeys.paisBancario, ConfigOpenBanking.pais);
  }

  // Proveedor elegido con las credenciales guardadas
  static ProveedorBancario crear({http.Client? cliente}) {
    final prueba = proveedorDePrueba;
    if (prueba != null) return prueba();
    switch (proveedor) {
      case TipoProveedor.enableBanking:
        return EnableBanking(idAplicacion: idAplicacion, clavePrivadaPem: clavePrivada, cliente: cliente);
    }
  }
}
