import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/servicios/detector_tarjetas.dart';

enum TipoTarjeta { debito, credito, prepago }

// Tarjeta guardada. Nunca se guarda el número completo: solo red, banco y últimos 4 dígitos.
// El nombre (ej. "Visa BBVA ••1234") es lo que se guarda en cada movimiento pagado con ella.
class Tarjeta {
  final String nombre;
  final String? red; // 'Visa', 'Mastercard'…
  final TipoTarjeta? tipo;
  final String? ultimos4;
  final String? bancoId; // id en CatalogoBancos
  final String? cuentaId; // Cuenta bancaria asociada (solo informativo)

  const Tarjeta({required this.nombre, this.red, this.tipo, this.ultimos4, this.bancoId, this.cuentaId});

  // A partir de un nombre libre o detectado ("Visa ••1234") intenta sacar red y últimos 4
  factory Tarjeta.desdeNombre(String nombre) => Tarjeta(
        nombre: nombre,
        red: DetectorTarjetas.red(nombre),
        ultimos4: DetectorTarjetas.ultimosDigitos(nombre),
      );

  BancoCatalogo? get banco => CatalogoBancos.porId(bancoId);

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        if (red != null) 'red': red,
        if (tipo != null) 'tipo': tipo!.name,
        if (ultimos4 != null) 'ultimos4': ultimos4,
        if (bancoId != null) 'bancoId': bancoId,
        if (cuentaId != null) 'cuentaId': cuentaId,
      };

  // Las tarjetas guardadas antes eran solo un texto
  factory Tarjeta.fromJson(dynamic json) {
    if (json is! Map) return Tarjeta.desdeNombre(json.toString());
    return Tarjeta(
      nombre: json['nombre'],
      red: json['red'],
      tipo: TipoTarjeta.values.where((t) => t.name == json['tipo']).firstOrNull,
      ultimos4: json['ultimos4'],
      bancoId: json['bancoId'],
      cuentaId: json['cuentaId'],
    );
  }
}

// Tarjetas guardadas por el usuario.
class ServicioTarjetas {
  // Solo los nombres (los que se eligen en el formulario y se guardan en los movimientos)
  static Future<List<String>> cargar() async => (await cargarTarjetas()).map((t) => t.nombre).toList();

  static Future<List<Tarjeta>> cargarTarjetas() async {
    final prefs = await SharedPreferences.getInstance();
    final List<dynamic> lista = jsonDecode(prefs.getString(DBKeys.tarjetas) ?? '[]');
    return lista.map(Tarjeta.fromJson).toList();
  }

  static Future<void> _guardarTarjetas(List<Tarjeta> tarjetas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DBKeys.tarjetas, jsonEncode(tarjetas.map((t) => t.toJson()).toList()));
  }

  // Devuelve false si el nombre está vacío o ya existe
  static Future<bool> anadir(String nombre) => anadirTarjeta(Tarjeta.desdeNombre(nombre.trim()));

  static Future<bool> anadirTarjeta(Tarjeta tarjeta) async {
    final tarjetas = await cargarTarjetas();
    if (tarjeta.nombre.trim().isEmpty || _contiene(tarjetas.map((t) => t.nombre), tarjeta.nombre)) return false;
    await _guardarTarjetas([...tarjetas, tarjeta]);
    return true;
  }

  static Future<void> eliminar(String nombre) async {
    final tarjetas = await cargarTarjetas();
    await _guardarTarjetas(tarjetas.where((t) => t.nombre.toLowerCase() != nombre.toLowerCase()).toList());
  }

  // --- Tarjetas detectadas en notificaciones, pendientes de que el usuario las acepte ---

  static Future<List<String>> cargarDetectadas() => _leer(DBKeys.tarjetasDetectadas);

  // Devuelve true si es nueva (no guardada, no descartada y no pendiente ya)
  static Future<bool> anadirDetectada(String nombre) async {
    final detectadas = await cargarDetectadas();
    if (_contiene(detectadas, nombre) ||
        _contiene(await cargar(), nombre) ||
        _contiene(await _leer(DBKeys.tarjetasDescartadas), nombre)) {
      return false;
    }
    detectadas.add(nombre);
    await _escribir(DBKeys.tarjetasDetectadas, detectadas);
    return true;
  }

  static Future<void> aceptarDetectada(String nombre) async {
    await anadir(nombre);
    await _quitarDetectada(nombre);
  }

  // No se volverá a proponer
  static Future<void> descartarDetectada(String nombre) async {
    final descartadas = await _leer(DBKeys.tarjetasDescartadas);
    if (!_contiene(descartadas, nombre)) await _escribir(DBKeys.tarjetasDescartadas, [...descartadas, nombre]);
    await _quitarDetectada(nombre);
  }

  static Future<void> _quitarDetectada(String nombre) async {
    final detectadas = await cargarDetectadas();
    detectadas.removeWhere((t) => t.toLowerCase() == nombre.toLowerCase());
    await _escribir(DBKeys.tarjetasDetectadas, detectadas);
  }

  static bool _contiene(Iterable<String> lista, String nombre) =>
      lista.any((t) => t.toLowerCase() == nombre.trim().toLowerCase());

  static Future<List<String>> _leer(String clave) async {
    final prefs = await SharedPreferences.getInstance();
    final List<dynamic> lista = jsonDecode(prefs.getString(clave) ?? '[]');
    return lista.map((e) => e.toString()).toList();
  }

  static Future<void> _escribir(String clave, List<String> lista) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, jsonEncode(lista));
  }
}
