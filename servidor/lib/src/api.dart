import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'almacen.dart';
import 'configuracion.dart';
import 'limitador.dart';
import 'panel/panel.dart';
import 'seguridad.dart';

// Errores de la API: siempre {"error": "<código>"} para que la app los traduzca a sus 4 idiomas
class ErrorApi implements Exception {
  final int estado;
  final String codigo;
  const ErrorApi(this.estado, this.codigo);
}

const _json = {'content-type': 'application/json; charset=utf-8'};
const _contextoDispositivo = 'onbudget.dispositivo';
const _longitudSalAcceso = 16;
const _minBytesHuella = 32;
const _maxBytesClave = 4096;

Response _respuesta(Object cuerpo, {int estado = 200}) => Response(estado, body: jsonEncode(cuerpo), headers: _json);

// API HTTP del servidor (v2: usuarios y bóvedas compartidas con permisos).
// Solo ve bloques cifrados: no puede leer importes, conceptos ni nombres de bóveda.
// Lo que sí hace cumplir es quién puede leer y quién puede escribir en cada bóveda.
class ApiServidor {
  final Almacen almacen;
  final Configuracion config;
  final LimitadorIntentos _limitador;
  // Cabecera con la IP real del cliente cuando hay un proxy delante (Nginx, Caddy, Tailscale)
  final String cabeceraIp;
  // Panel web /admin. Sin ADMIN_TOKEN solo informa de que está desactivado.
  final PanelAdmin panel;

  ApiServidor(this.almacen, this.config, {this.cabeceraIp = 'x-real-ip', DateTime Function()? ahora})
    : _limitador = LimitadorIntentos(
        maximo: config.intentosSesionPermitidos,
        ventana: config.ventanaIntentosSesion,
        ahora: ahora,
      ),
      panel = PanelAdmin(almacen, config, cabeceraIp: cabeceraIp, ahora: ahora);

  Handler get handler {
    final publico = Router()
      ..get('/salud', _salud)
      ..post('/v2/usuarios', _registrar)
      ..get('/v2/usuarios/<nombre>/kdf', _kdf)
      ..post('/v2/sesion', _abrirSesion);

    final privado = Router()
      ..delete('/v2/sesion', _cerrarSesion)
      ..get('/v2/yo', _yo)
      ..delete('/v2/yo', _borrarCuenta)
      ..get('/v2/usuarios/<nombre>/clave-publica', _clavePublica)
      ..get('/v2/dispositivos', _listarDispositivos)
      ..delete('/v2/dispositivos/<id>', _revocarDispositivo)
      ..get('/v2/bovedas', _listarBovedas)
      ..post('/v2/bovedas', _crearBoveda)
      ..delete('/v2/bovedas/<boveda>', _borrarBoveda)
      ..get('/v2/bovedas/<boveda>/miembros', _listarMiembros)
      ..put('/v2/bovedas/<boveda>/miembros/<nombre>', _guardarMiembro)
      ..delete('/v2/bovedas/<boveda>/miembros/<nombre>', _quitarMiembro)
      ..post('/v2/bovedas/<boveda>/cambios', _subirCambios)
      ..get('/v2/bovedas/<boveda>/cambios', _bajarCambios)
      ..get('/v2/bovedas/<boveda>/instantanea', _bajarInstantanea)
      ..put('/v2/bovedas/<boveda>/instantanea', _subirInstantanea);

    final conSesion = const Pipeline().addMiddleware(_exigirSesion()).addHandler(privado.call);
    final api = Cascade(statusCodes: [404, 405]).add(publico.call).add(conSesion).handler;
    final panelHandler = panel.handler;

    return const Pipeline().addMiddleware(_cabecerasSeguridad()).addMiddleware(_gestionarErrores()).addHandler((r) {
      // El panel web vive bajo /admin; el resto es la API de la app
      final ruta = r.url.path;
      if (ruta == 'admin' || ruta.startsWith('admin/')) return panelHandler(r);
      return api(r);
    });
  }

  // --- Middleware ---

  Middleware _gestionarErrores() =>
      (inner) => (request) async {
        try {
          return await inner(request);
        } on ErrorApi catch (e) {
          return _respuesta({'error': e.codigo}, estado: e.estado);
        } on FormatException {
          return _respuesta({'error': 'peticion_invalida'}, estado: 400);
        }
      };

  Middleware _cabecerasSeguridad() =>
      (inner) => (request) async {
        final r = await inner(request);
        return r.change(
          headers: {
            if (!r.headers.containsKey('cache-control')) 'cache-control': 'no-store',
            'x-content-type-options': 'nosniff',
            'referrer-policy': 'no-referrer',
          },
        );
      };

  Middleware _exigirSesion() =>
      (inner) => (request) async {
        final cabecera = request.headers['authorization'] ?? '';
        if (!cabecera.startsWith('Bearer ')) {
          // Rutas que no existen ni en pública ni en privada siguen siendo 404
          if (!request.url.path.startsWith('v2/')) return Response.notFound(null);
          throw const ErrorApi(401, 'sin_sesion');
        }
        final dispositivo = almacen.dispositivoPorToken(cabecera.substring(7).trim());
        if (dispositivo == null) throw const ErrorApi(401, 'sesion_invalida');
        return inner(request.change(context: {_contextoDispositivo: dispositivo}));
      };

  Dispositivo _dispositivo(Request r) => r.context[_contextoDispositivo] as Dispositivo;

  // Comprueba que quien llama es miembro de la bóveda con permiso suficiente.
  // A quien no es miembro se le dice que no existe, para no revelar qué bóvedas hay.
  Miembro _exigirMiembro(Request r, String boveda, {bool escribir = false, bool propietario = false}) {
    final m = almacen.miembro(boveda, _dispositivo(r).usuario);
    if (m == null) throw const ErrorApi(404, 'boveda_no_existe');
    if (propietario && !m.rol.esPropietario) throw const ErrorApi(403, 'solo_propietario');
    if (escribir && !m.rol.puedeEscribir) throw const ErrorApi(403, 'solo_lectura');
    return m;
  }

  String _ip(Request r) {
    final cabecera = r.headers[cabeceraIp];
    if (cabecera != null && cabecera.isNotEmpty) return cabecera.split(',').first.trim();
    final info = r.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'desconocida';
  }

  // Lee el cuerpo JSON sin pasar del tamaño máximo (no se confía en content-length)
  Future<Map<String, Object?>> _leerJson(Request r) async {
    final bytes = BytesBuilder(copy: false);
    await for (final trozo in r.read()) {
      bytes.add(trozo);
      if (bytes.length > config.maxBytesCuerpo) throw const ErrorApi(413, 'demasiado_grande');
    }
    final valor = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (valor is! Map) throw const ErrorApi(400, 'peticion_invalida');
    return valor.cast<String, Object?>();
  }

  static String _texto(Map<String, Object?> m, String clave, {int max = 200}) {
    final v = m[clave];
    if (v is! String || v.trim().isEmpty || v.length > max) throw ErrorApi(400, 'falta_$clave');
    return v.trim();
  }

  static Uint8List _binario(Map<String, Object?> m, String clave, {int max = _maxBytesClave}) {
    final v = m[clave];
    if (v is! String) throw ErrorApi(400, 'falta_$clave');
    final Uint8List datos;
    try {
      datos = base64.decode(v);
    } on FormatException {
      throw ErrorApi(400, 'falta_$clave');
    }
    if (datos.isEmpty || datos.length > max) throw ErrorApi(400, 'falta_$clave');
    return datos;
  }

  static ({String id, String nombre}) _datosDispositivo(Map<String, Object?> m) {
    final d = m['dispositivo'];
    if (d is! Map) throw const ErrorApi(400, 'falta_dispositivo');
    final mapa = d.cast<String, Object?>();
    return (id: _texto(mapa, 'id', max: 64), nombre: _texto(mapa, 'nombre', max: 80));
  }

  bool _huellaCorrecta(Usuario u, List<int> huella) => igualesSeguro(hashConSal(u.salAcceso, huella), u.hashAcceso);

  Map<String, Object?> _datosSesion(Usuario u, String token) => {
    'token': token,
    'usuario': u.nombre,
    'kdf': u.kdf,
    'clavePublica': base64.encode(u.clavePublica),
    'clavePrivadaCifrada': base64.encode(u.clavePrivadaCifrada),
  };

  // --- Rutas públicas ---

  Response _salud(Request r) =>
      _respuesta({'estado': 'ok', 'version': Configuracion.versionServidor, 'api': Configuracion.versionApi});

  // Registro: exige un código de invitación de un solo uso creado por el administrador
  Future<Response> _registrar(Request r) async {
    final cuerpo = await _leerJson(r);
    final invitacion = _texto(cuerpo, 'invitacion', max: 40);
    final nombre = Almacen.normalizarNombre(_texto(cuerpo, 'nombre', max: 32));
    if (!Almacen.nombreValido(nombre)) throw const ErrorApi(400, 'nombre_invalido');
    final kdf = cuerpo['kdf'];
    if (kdf is! Map || kdf.isEmpty) throw const ErrorApi(400, 'falta_kdf');
    final huella = _binario(cuerpo, 'huellaAcceso');
    if (huella.length < _minBytesHuella) throw const ErrorApi(400, 'falta_huellaAcceso');
    final publica = _binario(cuerpo, 'clavePublica');
    final privada = _binario(cuerpo, 'clavePrivadaCifrada');
    final disp = _datosDispositivo(cuerpo);

    final ip = _ip(r);
    if (_limitador.bloqueado(ip)) throw const ErrorApi(429, 'demasiados_intentos');
    final sal = bytesAleatorios(_longitudSalAcceso);
    final Usuario? u;
    try {
      u = almacen.registrarUsuario(
        invitacion: invitacion,
        nombre: nombre,
        kdf: kdf.cast<String, Object?>(),
        salAcceso: sal,
        hashAcceso: hashConSal(sal, huella),
        clavePublica: publica,
        clavePrivadaCifrada: privada,
      );
    } on SqliteException {
      // Nombre repetido: la invitación no se gasta (la transacción se deshace).
      // Solo llega aquí quien tiene una invitación válida, así que no revela usuarios a extraños.
      throw const ErrorApi(409, 'nombre_en_uso');
    }
    if (u == null) {
      _limitador.registrarFallo(ip);
      throw const ErrorApi(403, 'invitacion_invalida');
    }
    final token = almacen.abrirSesion(u.id, disp.id, disp.nombre);
    return _respuesta(_datosSesion(u, token), estado: 201);
  }

  // Parámetros para que la app derive la clave antes de iniciar sesión (como el "prelogin" de Bitwarden).
  // Para un nombre que no existe se devuelven parámetros falsos pero estables, para no revelar quién tiene cuenta.
  Response _kdf(Request r, String nombre) {
    final u = almacen.usuarioPorNombre(Uri.decodeComponent(nombre));
    if (u != null) return _respuesta({'kdf': u.kdf});
    final hex = hashDe('kdf-falso:${Almacen.normalizarNombre(nombre)}:${config.rutaBaseDatos}');
    final sal = [for (var i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    return _respuesta({
      'kdf': {
        'algoritmo': 'argon2id',
        'memoriaKiB': 65536,
        'iteraciones': 3,
        'paralelismo': 1,
        'sal': base64.encode(sal),
      },
    });
  }

  Future<Response> _abrirSesion(Request r) async {
    final cuerpo = await _leerJson(r);
    final nombre = _texto(cuerpo, 'nombre', max: 32);
    final huella = _binario(cuerpo, 'huellaAcceso');
    final disp = _datosDispositivo(cuerpo);

    final ip = _ip(r);
    if (_limitador.bloqueado(ip)) throw const ErrorApi(429, 'demasiados_intentos');
    final u = almacen.usuarioPorNombre(nombre);
    // Mismo error si el usuario no existe, está desactivado o la contraseña es incorrecta: no se revela cuál falla
    if (u == null || u.desactivado || !_huellaCorrecta(u, huella)) {
      _limitador.registrarFallo(ip);
      throw const ErrorApi(401, 'credenciales_incorrectas');
    }
    _limitador.limpiar(ip);
    return _respuesta(_datosSesion(u, almacen.abrirSesion(u.id, disp.id, disp.nombre)));
  }

  // --- Cuenta y dispositivos ---

  Response _cerrarSesion(Request r) {
    final d = _dispositivo(r);
    almacen.revocarDispositivo(d.usuario, d.id);
    return Response(204);
  }

  Response _yo(Request r) {
    final d = _dispositivo(r);
    final u = almacen.usuario(d.usuario)!;
    return _respuesta({'usuario': u.nombre, 'dispositivo': d.id, 'creado': u.creado.toIso8601String()});
  }

  // Borrar la cuenta desde la app (exigido por Apple). Pide de nuevo la contraseña.
  // También borra las bóvedas de las que era el único propietario.
  Future<Response> _borrarCuenta(Request r) async {
    final u = almacen.usuario(_dispositivo(r).usuario)!;
    if (!_huellaCorrecta(u, _binario(await _leerJson(r), 'huellaAcceso'))) {
      throw const ErrorApi(401, 'credenciales_incorrectas');
    }
    almacen.borrarUsuario(u.id);
    return Response(204);
  }

  // Clave pública de otro usuario, para compartirle la clave de una bóveda
  Response _clavePublica(Request r, String nombre) {
    final u = almacen.usuarioPorNombre(Uri.decodeComponent(nombre));
    if (u == null || u.desactivado) throw const ErrorApi(404, 'usuario_no_existe');
    return _respuesta({'usuario': u.nombre, 'clavePublica': base64.encode(u.clavePublica)});
  }

  Response _listarDispositivos(Request r) {
    final d = _dispositivo(r);
    return _respuesta({
      'actual': d.id,
      'dispositivos': almacen.dispositivos(d.usuario).map((x) => x.toJson()).toList(),
    });
  }

  Response _revocarDispositivo(Request r, String id) {
    if (!almacen.revocarDispositivo(_dispositivo(r).usuario, Uri.decodeComponent(id))) {
      throw const ErrorApi(404, 'dispositivo_no_existe');
    }
    return Response(204);
  }

  // --- Bóvedas y miembros ---

  Response _listarBovedas(Request r) => _respuesta({
    'bovedas': almacen
        .bovedasDe(_dispositivo(r).usuario)
        .map(
          (x) => {
            'id': x.boveda.id,
            'nombreCifrado': base64.encode(x.boveda.nombreCifrado),
            'rol': x.miembro.rol.name,
            'claveBovedaCifrada': base64.encode(x.miembro.claveBovedaCifrada),
            'creada': x.boveda.creada.toIso8601String(),
          },
        )
        .toList(),
  });

  Future<Response> _crearBoveda(Request r) async {
    final cuerpo = await _leerJson(r);
    final b = almacen.crearBoveda(
      _dispositivo(r).usuario,
      _binario(cuerpo, 'nombreCifrado'),
      _binario(cuerpo, 'claveBovedaCifrada'),
    );
    return _respuesta({'id': b.id, 'rol': Rol.propietario.name}, estado: 201);
  }

  // Pide de nuevo la contraseña del propietario
  Future<Response> _borrarBoveda(Request r, String boveda) async {
    _exigirMiembro(r, boveda, propietario: true);
    final u = almacen.usuario(_dispositivo(r).usuario)!;
    if (!_huellaCorrecta(u, _binario(await _leerJson(r), 'huellaAcceso'))) {
      throw const ErrorApi(401, 'credenciales_incorrectas');
    }
    almacen.borrarBoveda(boveda);
    return Response(204);
  }

  Response _listarMiembros(Request r, String boveda) {
    _exigirMiembro(r, boveda);
    return _respuesta({'miembros': almacen.miembros(boveda).map((m) => m.toJson()).toList()});
  }

  // Añade un miembro o le cambia el rol (solo propietarios). Al añadirlo hay que enviar la clave
  // de la bóveda cifrada con la clave pública de ese usuario.
  Future<Response> _guardarMiembro(Request r, String boveda, String nombre) async {
    _exigirMiembro(r, boveda, propietario: true);
    final cuerpo = await _leerJson(r);
    final rol = Rol.leer(cuerpo['rol']);
    if (rol == null) throw const ErrorApi(400, 'rol_invalido');
    final u = almacen.usuarioPorNombre(Uri.decodeComponent(nombre));
    if (u == null || u.desactivado) throw const ErrorApi(404, 'usuario_no_existe');
    final clave = cuerpo.containsKey('claveBovedaCifrada') ? _binario(cuerpo, 'claveBovedaCifrada') : null;
    if (clave == null && almacen.miembro(boveda, u.id) == null) throw const ErrorApi(400, 'falta_claveBovedaCifrada');
    if (!almacen.guardarMiembro(boveda, u.id, rol, clave)) throw const ErrorApi(409, 'ultimo_propietario');
    return Response(204);
  }

  // Un propietario puede quitar a cualquiera; cualquier miembro puede salirse
  Response _quitarMiembro(Request r, String boveda, String nombre) {
    final yo = _exigirMiembro(r, boveda);
    final u = almacen.usuarioPorNombre(Uri.decodeComponent(nombre));
    if (u == null || almacen.miembro(boveda, u.id) == null) throw const ErrorApi(404, 'usuario_no_existe');
    if (u.id != yo.usuario && !yo.rol.esPropietario) throw const ErrorApi(403, 'solo_propietario');
    if (!almacen.quitarMiembro(boveda, u.id)) throw const ErrorApi(409, 'ultimo_propietario');
    return Response(204);
  }

  // --- Cambios e instantáneas ---

  Future<Response> _subirCambios(Request r, String boveda) async {
    _exigirMiembro(r, boveda, escribir: true);
    final d = _dispositivo(r);
    final lista = (await _leerJson(r))['cambios'];
    if (lista is! List || lista.isEmpty) throw const ErrorApi(400, 'falta_cambios');
    if (lista.length > config.maxCambiosPorEnvio) throw const ErrorApi(413, 'demasiados_cambios');
    final paquetes = <Uint8List>[];
    for (final c in lista) {
      if (c is! String) throw const ErrorApi(400, 'falta_cambios');
      final datos = base64.decode(c);
      if (datos.isEmpty || datos.length > config.maxBytesCambio) throw const ErrorApi(413, 'cambio_demasiado_grande');
      paquetes.add(datos);
    }
    final secuencias = almacen.guardarCambios(boveda, d.usuario, d.id, paquetes);
    return _respuesta({'secuencias': secuencias, 'ultima': secuencias.last});
  }

  Response _bajarCambios(Request r, String boveda) {
    _exigirMiembro(r, boveda);
    final desde = int.tryParse(r.url.queryParameters['desde'] ?? '0') ?? -1;
    if (desde < 0) throw const ErrorApi(400, 'desde_invalido');
    final pedido = int.tryParse(r.url.queryParameters['limite'] ?? '') ?? config.maxCambiosPorDescarga;
    final limite = pedido.clamp(1, config.maxCambiosPorDescarga);

    // Si lo que falta ya se compactó en una instantánea, la app debe descargarla primero
    final inst = almacen.instantanea(boveda);
    if (inst != null && desde < inst.hasta) {
      throw const ErrorApi(409, 'instantanea_necesaria');
    }
    final cambios = almacen.cambiosDesde(boveda, desde, limite + 1);
    final hayMas = cambios.length > limite;
    final pagina = hayMas ? cambios.sublist(0, limite) : cambios;
    return _respuesta({
      'cambios': pagina.map((c) => c.toJson()).toList(),
      'ultima': almacen.ultimaSecuencia(boveda),
      'hayMas': hayMas,
    });
  }

  Response _bajarInstantanea(Request r, String boveda) {
    _exigirMiembro(r, boveda);
    final inst = almacen.instantanea(boveda);
    if (inst == null) throw const ErrorApi(404, 'sin_instantanea');
    return _respuesta({
      'hasta': inst.hasta,
      'dispositivo': inst.dispositivo,
      'datos': base64.encode(inst.datos),
      'fecha': inst.fecha.toIso8601String(),
    });
  }

  Future<Response> _subirInstantanea(Request r, String boveda) async {
    _exigirMiembro(r, boveda, escribir: true);
    final cuerpo = await _leerJson(r);
    final hasta = cuerpo['hasta'];
    if (hasta is! int || hasta < 0 || hasta > almacen.ultimaSecuencia(boveda)) {
      throw const ErrorApi(400, 'hasta_invalido');
    }
    final actual = almacen.instantanea(boveda);
    // Nunca se retrocede: una instantánea más antigua que la guardada perdería cambios
    if (actual != null && hasta < actual.hasta) throw const ErrorApi(409, 'instantanea_antigua');
    almacen.guardarInstantanea(
      boveda,
      _dispositivo(r).id,
      hasta,
      _binario(cuerpo, 'datos', max: config.maxBytesCuerpo),
    );
    return Response(204);
  }
}
