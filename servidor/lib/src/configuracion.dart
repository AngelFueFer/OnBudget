import 'dart:io';

import 'package:path/path.dart' as p;

// Ajustes del servidor, leídos de variables de entorno (como Vaultwarden).
// Ninguno es obligatorio: los valores por defecto sirven para Docker.
class Configuracion {
  static const String versionServidor = '0.3.0';
  static const int versionApi = 2;

  final String direccion;
  final int puerto;
  final String carpetaDatos;
  // HTTPS propio opcional: si se dan los dos, el servidor escucha en HTTPS directamente
  final String? certificadoTls;
  final String? claveTls;
  final int maxBytesCuerpo;
  final int maxBytesCambio;
  final int maxCambiosPorEnvio;
  final int maxCambiosPorDescarga;
  final int intentosSesionPermitidos;
  final Duration ventanaIntentosSesion;
  // Contraseña del panel /admin (texto o hash de "onbudget-servidor admin hash"). Sin ella, el panel está desactivado.
  final String? tokenAdmin;
  final Duration duracionSesionAdmin;

  const Configuracion({
    this.direccion = '0.0.0.0',
    this.puerto = 8080,
    this.carpetaDatos = '/datos',
    this.certificadoTls,
    this.claveTls,
    this.maxBytesCuerpo = 25 * 1024 * 1024,
    this.maxBytesCambio = 1024 * 1024,
    this.maxCambiosPorEnvio = 500,
    this.maxCambiosPorDescarga = 500,
    this.intentosSesionPermitidos = 10,
    this.ventanaIntentosSesion = const Duration(minutes: 15),
    this.tokenAdmin,
    this.duracionSesionAdmin = const Duration(minutes: 20),
  });

  factory Configuracion.desdeEntorno([Map<String, String>? entorno]) {
    final e = entorno ?? Platform.environment;
    String? texto(String clave) {
      final v = e[clave]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    int entero(String clave, int defecto) => int.tryParse(texto(clave) ?? '') ?? defecto;

    return Configuracion(
      direccion: texto('DIRECCION') ?? '0.0.0.0',
      puerto: entero('PUERTO', 8080),
      carpetaDatos: texto('CARPETA_DATOS') ?? '/datos',
      certificadoTls: texto('TLS_CERTIFICADO'),
      claveTls: texto('TLS_CLAVE'),
      maxBytesCuerpo: entero('MAX_MB_CUERPO', 25) * 1024 * 1024,
      tokenAdmin: texto('ADMIN_TOKEN'),
    );
  }

  bool get panelActivo => tokenAdmin != null;

  bool get usaTlsPropio => certificadoTls != null && claveTls != null;

  String get rutaBaseDatos => p.join(carpetaDatos, 'onbudget.sqlite3');
}
