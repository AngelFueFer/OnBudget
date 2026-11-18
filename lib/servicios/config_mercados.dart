import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';

// Conexión con los servidores de bolsa (EODHD), configurable por cada usuario:
// - viene desactivada: la app no hace ninguna llamada para las inversiones;
// - para conectarse cada usuario tiene que poner su propia clave (no hay clave compartida).
class ConfigMercados {
  static bool activa = false;
  static String _clave = '';

  // Clave que se envía a la API
  static String get clave => _clave;
  static bool get tieneClave => _clave.isNotEmpty;
  // Solo se llama a la API con la conexión activada y una clave puesta
  static bool get conectada => activa && tieneClave;

  static Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    activa = prefs.getBool(DBKeys.conexionMercados) ?? false;
    _clave = prefs.getString(DBKeys.claveApiMercados) ?? '';
  }

  static Future<void> cambiarActiva(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DBKeys.conexionMercados, valor);
    activa = valor;
  }

  static Future<void> guardarClave(String nueva) async {
    final prefs = await SharedPreferences.getInstance();
    _clave = nueva.trim();
    await prefs.setString(DBKeys.claveApiMercados, _clave);
  }
}
