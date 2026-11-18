import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'almacen.dart';
import 'api.dart';
import 'configuracion.dart';
import 'token_admin.dart';

const String ayuda =
    '''
On Budget · servidor de sincronización ${Configuracion.versionServidor}

Uso: onbudget-servidor <comando>

  servir                               Arranca el servidor (por defecto)
  invitacion crear                     Crea un código de un solo uso para registrar un usuario desde la app
  invitacion anular                    Anula todos los códigos sin usar
  usuarios listar                      Lista los usuarios
  usuarios desactivar <nombre>         Impide entrar a un usuario y cierra sus sesiones (no borra nada)
  usuarios activar <nombre>            Vuelve a permitirle entrar
  usuarios borrar <nombre>             Borra un usuario y las bóvedas de las que es el único propietario
  bovedas listar                       Lista las bóvedas
  bovedas borrar <id>                  Borra una bóveda y todos sus datos (no se puede deshacer)
  dispositivos listar <usuario>        Lista los dispositivos de un usuario
  dispositivos revocar <usuario> <id>  Cierra la sesión de un dispositivo (p. ej. un móvil perdido)
  admin hash [contraseña]              Genera el hash para ADMIN_TOKEN (si no se pasa, la pide)
  ayuda                                Muestra esta ayuda

Variables de entorno: PUERTO (8080), DIRECCION (0.0.0.0), CARPETA_DATOS (/datos),
TLS_CERTIFICADO y TLS_CLAVE (HTTPS propio, opcional), MAX_MB_CUERPO (25), CABECERA_IP (X-Real-IP),
ADMIN_TOKEN (activa el panel web /admin).
''';

// Ejecuta un comando y devuelve el código de salida. [salida] es sustituible en tests.
Future<int> ejecutar(List<String> args, {Configuracion? config, Almacen? almacen, StringSink? salida}) async {
  final out = salida ?? stdout;
  final cfg = config ?? Configuracion.desdeEntorno();
  final comando = args.isEmpty ? 'servir' : args.first;

  if (comando == 'ayuda' || comando == '--help' || comando == '-h') {
    out.write(ayuda);
    return 0;
  }

  Almacen abrir() {
    if (almacen != null) return almacen;
    Directory(cfg.carpetaDatos).createSync(recursive: true);
    return Almacen.abrir(cfg.rutaBaseDatos);
  }

  final sub = args.length > 1 ? args[1] : '';
  switch ((comando, sub)) {
    case ('servir', _):
      await servir(cfg, abrir(), salida: out);
      return 0;
    case ('admin', 'hash'):
      var contrasena = args.length > 2 ? args[2] : null;
      if (contrasena == null) {
        stdout.write('Contraseña del panel: ');
        if (stdin.hasTerminal) stdin.echoMode = false;
        contrasena = stdin.readLineSync() ?? '';
        if (stdin.hasTerminal) stdin.echoMode = true;
        stdout.writeln();
      }
      if (contrasena.length < 12) {
        out.writeln('Usa al menos 12 caracteres.');
        return 1;
      }
      out.writeln(hashTokenAdmin(contrasena));
      out.writeln(r'En docker-compose.yml escribe cada $ como $$ (Compose interpreta $).');
      return 0;
    case ('invitacion', 'crear'):
      final codigo = abrir().crearInvitacion();
      out.writeln('Código de invitación (un solo uso): $codigo');
      out.writeln('Escríbelo en la app al elegir "Crear cuenta en mi servidor".');
      return 0;
    case ('invitacion', 'anular'):
      abrir().anularInvitaciones();
      out.writeln('Invitaciones sin usar anuladas.');
      return 0;
    case ('usuarios', 'listar'):
      final lista = abrir().usuarios();
      if (lista.isEmpty) out.writeln('No hay usuarios.');
      for (final u in lista) {
        final estado = u.desactivado ? 'desactivado' : 'activo';
        out.writeln('${u.nombre}  $estado  bóvedas: ${u.bovedas}  dispositivos: ${u.dispositivos}');
      }
      return 0;
    case ('usuarios', 'desactivar' || 'activar' || 'borrar') when args.length == 3:
      final a = abrir();
      final u = a.usuarioPorNombre(args[2]);
      if (u == null) {
        out.writeln('No existe ese usuario.');
        return 1;
      }
      if (sub == 'borrar') {
        a.borrarUsuario(u.id);
        out.writeln('Usuario borrado.');
      } else {
        a.desactivarUsuario(u.id, sub == 'desactivar');
        out.writeln(sub == 'desactivar' ? 'Usuario desactivado y sesiones cerradas.' : 'Usuario activado.');
      }
      return 0;
    case ('bovedas', 'listar'):
      final lista = abrir().bovedas();
      if (lista.isEmpty) out.writeln('No hay bóvedas.');
      for (final b in lista) {
        out.writeln('${b.id}  creada ${b.creada.toIso8601String()}  miembros: ${b.miembros}  cambios: ${b.cambios}');
      }
      return 0;
    case ('bovedas', 'borrar') when args.length == 3:
      final ok = abrir().borrarBoveda(args[2]);
      out.writeln(ok ? 'Bóveda borrada.' : 'No existe esa bóveda.');
      return ok ? 0 : 1;
    case ('dispositivos', 'listar' || 'revocar') when args.length == (sub == 'listar' ? 3 : 4):
      final a = abrir();
      final u = a.usuarioPorNombre(args[2]);
      if (u == null) {
        out.writeln('No existe ese usuario.');
        return 1;
      }
      if (sub == 'revocar') {
        final ok = a.revocarDispositivo(u.id, args[3]);
        out.writeln(ok ? 'Sesión del dispositivo cerrada.' : 'No existe ese dispositivo activo.');
        return ok ? 0 : 1;
      }
      final lista = a.dispositivos(u.id);
      if (lista.isEmpty) out.writeln('No hay dispositivos.');
      for (final d in lista) {
        final estado = d.revocado ? 'revocado' : 'activo';
        out.writeln('${d.id}  "${d.nombre}"  $estado  último acceso: ${d.ultimoAcceso?.toIso8601String() ?? '-'}');
      }
      return 0;
    default:
      out.write(ayuda);
      return 64; // EX_USAGE
  }
}

Future<HttpServer> servir(Configuracion cfg, Almacen almacen, {StringSink? salida}) async {
  final out = salida ?? stdout;
  final cabeceraIp = (Platform.environment['CABECERA_IP'] ?? 'X-Real-IP').toLowerCase();
  final api = ApiServidor(almacen, cfg, cabeceraIp: cabeceraIp);

  SecurityContext? contexto;
  if (cfg.usaTlsPropio) {
    contexto = SecurityContext()
      ..useCertificateChain(cfg.certificadoTls!)
      ..usePrivateKey(cfg.claveTls!);
  }
  final servidor = await shelf_io.serve(api.handler, cfg.direccion, cfg.puerto, securityContext: contexto);
  servidor.autoCompress = true;
  final esquema = contexto == null ? 'http' : 'https';
  out.writeln(
    'On Budget servidor ${Configuracion.versionServidor} escuchando en $esquema://${cfg.direccion}:${cfg.puerto}',
  );
  if (contexto == null) {
    out.writeln('Aviso: sin TLS propio. Ponlo detrás de un proxy con HTTPS (Nginx, Caddy) o usa Tailscale.');
  }
  if (cfg.tokenAdmin == null) {
    out.writeln('Panel /admin desactivado (define ADMIN_TOKEN para activarlo).');
  } else {
    out.writeln('Panel de administración en /admin');
    if (!tokenAdminEsHash(cfg.tokenAdmin!)) {
      out.writeln('Aviso: ADMIN_TOKEN está en texto plano. Genera un hash con: onbudget-servidor admin hash');
    }
  }
  if (almacen.usuarios().isEmpty && almacen.invitacionesPendientes() == 0) {
    out.writeln('Aún no hay usuarios. Crea una invitación con: onbudget-servidor invitacion crear');
  }
  return servidor;
}
