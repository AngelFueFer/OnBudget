import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:onbudget_servidor/onbudget_servidor.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

// Pruebas de extremo a extremo: servidor real en un puerto libre con base de datos en memoria
void main() {
  late Almacen almacen;
  late HttpServer servidor;
  late Uri base;
  final huella = base64.encode(List.filled(32, 7));
  final huellaMala = base64.encode(List.filled(32, 8));
  String b64(String texto) => base64.encode(utf8.encode(texto));
  const kdf = {'algoritmo': 'argon2id', 'sal': 'c2Fs', 'memoriaKiB': 65536, 'iteraciones': 3};

  setUp(() async {
    almacen = Almacen.enMemoria();
    const config = Configuracion(direccion: '127.0.0.1', puerto: 0, intentosSesionPermitidos: 3);
    servidor = await servir(config, almacen, salida: StringBuffer());
    base = Uri.parse('http://127.0.0.1:${servidor.port}');
  });

  tearDown(() async {
    await servidor.close(force: true);
    almacen.cerrar();
  });

  Future<http.Response> enviar(
    String metodo,
    String ruta, {
    Object? cuerpo,
    String? token,
    Map<String, String>? cabeceras,
  }) {
    final peticion = http.Request(metodo, base.resolve(ruta));
    if (cuerpo != null) peticion.body = jsonEncode(cuerpo);
    if (token != null) peticion.headers['authorization'] = 'Bearer $token';
    if (cabeceras != null) peticion.headers.addAll(cabeceras);
    return peticion.send().then(http.Response.fromStream);
  }

  Map<String, dynamic> json(http.Response r) => jsonDecode(r.body) as Map<String, dynamic>;

  Map<String, Object?> cuerpoRegistro(String nombre, {String? invitacion}) => {
    'invitacion': invitacion ?? almacen.crearInvitacion(),
    'nombre': nombre,
    'kdf': kdf,
    'huellaAcceso': huella,
    'clavePublica': b64('publica-$nombre'),
    'clavePrivadaCifrada': b64('privada-cifrada-$nombre'),
    'dispositivo': {'id': 'movil-$nombre', 'nombre': 'Móvil de $nombre'},
  };

  // Registra un usuario y devuelve su token
  Future<String> registrar(String nombre) async {
    final r = await enviar('POST', '/v2/usuarios', cuerpo: cuerpoRegistro(nombre));
    expect(r.statusCode, 201, reason: r.body);
    return json(r)['token'] as String;
  }

  Future<String> crearBoveda(String token) async {
    final r = await enviar(
      'POST',
      '/v2/bovedas',
      token: token,
      cuerpo: {'nombreCifrado': b64('Casa'), 'claveBovedaCifrada': b64('clave-para-propietario')},
    );
    expect(r.statusCode, 201, reason: r.body);
    return json(r)['id'] as String;
  }

  Future<http.Response> compartir(String token, String boveda, String nombre, String rol, {bool conClave = true}) =>
      enviar(
        'PUT',
        '/v2/bovedas/$boveda/miembros/$nombre',
        token: token,
        cuerpo: {'rol': rol, if (conClave) 'claveBovedaCifrada': b64('clave-para-$nombre')},
      );

  group('Salud y cabeceras', () {
    test('/salud responde con la versión y cabeceras de seguridad', () async {
      final r = await enviar('GET', '/salud');
      expect(r.statusCode, 200);
      expect(json(r)['api'], Configuracion.versionApi);
      expect(r.headers['cache-control'], 'no-store');
    });

    test('una ruta inexistente da 404 y una privada sin sesión da 401', () async {
      expect((await enviar('GET', '/nada')).statusCode, 404);
      final r = await enviar('GET', '/v2/bovedas');
      expect(r.statusCode, 401);
      expect(json(r)['error'], 'sin_sesion');
    });
  });

  group('Registro de usuarios', () {
    test('sin invitación válida no se puede registrar nadie', () async {
      final r = await enviar('POST', '/v2/usuarios', cuerpo: cuerpoRegistro('ana', invitacion: 'AAAA-BBBB-CCCC-DDDD'));
      expect(r.statusCode, 403);
      expect(json(r)['error'], 'invitacion_invalida');
      expect(almacen.usuarios(), isEmpty);
    });

    test('una invitación solo sirve una vez y acepta minúsculas y espacios', () async {
      final codigo = almacen.crearInvitacion();
      expect(almacen.consumirInvitacion(' ${codigo.toLowerCase().replaceAll('-', ' ')} '), isTrue);
      expect(almacen.consumirInvitacion(codigo), isFalse);
    });

    test('el registro devuelve sesión y las claves, y el nombre se guarda en minúsculas', () async {
      final r = await enviar('POST', '/v2/usuarios', cuerpo: cuerpoRegistro('Ana'));
      expect(r.statusCode, 201);
      expect(json(r)['usuario'], 'ana');
      expect(json(r)['clavePrivadaCifrada'], b64('privada-cifrada-Ana'));
      final yo = await enviar('GET', '/v2/yo', token: json(r)['token'] as String);
      expect(json(yo)['usuario'], 'ana');
    });

    test('el servidor no guarda la huella de acceso tal cual', () async {
      await registrar('ana');
      expect(almacen.usuarioPorNombre('ana')!.hashAcceso, isNot(contains(huella)));
    });

    test('un nombre repetido da 409 y no gasta la invitación', () async {
      await registrar('ana');
      final invitacion = almacen.crearInvitacion();
      final r = await enviar('POST', '/v2/usuarios', cuerpo: cuerpoRegistro('ANA', invitacion: invitacion));
      expect(r.statusCode, 409);
      expect(json(r)['error'], 'nombre_en_uso');
      final otro = await enviar('POST', '/v2/usuarios', cuerpo: cuerpoRegistro('luis', invitacion: invitacion));
      expect(otro.statusCode, 201);
    });

    test('nombres no válidos y peticiones mal formadas dan 400', () async {
      final r = await enviar('POST', '/v2/usuarios', cuerpo: cuerpoRegistro('a b'));
      expect(json(r)['error'], 'nombre_invalido');
      final sinKdf = await enviar('POST', '/v2/usuarios', cuerpo: {'invitacion': 'x', 'nombre': 'ana'});
      expect(json(sinKdf)['error'], 'falta_kdf');
      expect((await http.post(base.resolve('/v2/sesion'), body: '{no json')).statusCode, 400);
    });

    test('kdf no revela si un usuario existe', () async {
      await registrar('ana');
      expect(json(await enviar('GET', '/v2/usuarios/ana/kdf'))['kdf'], kdf);
      final falso1 = await enviar('GET', '/v2/usuarios/nadie/kdf');
      final falso2 = await enviar('GET', '/v2/usuarios/nadie/kdf');
      expect(falso1.statusCode, 200);
      expect(falso1.body, falso2.body, reason: 'Estable entre peticiones');
    });
  });

  group('Sesiones', () {
    test('otro dispositivo entra con la huella y recibe sus claves', () async {
      await registrar('ana');
      final r = await enviar(
        'POST',
        '/v2/sesion',
        cuerpo: {
          'nombre': 'Ana',
          'huellaAcceso': huella,
          'dispositivo': {'id': 'tablet', 'nombre': 'Tablet'},
        },
      );
      expect(r.statusCode, 200);
      expect(json(r)['clavePublica'], b64('publica-ana'));
      final lista = await enviar('GET', '/v2/dispositivos', token: json(r)['token'] as String);
      expect((json(lista)['dispositivos'] as List).length, 2);
    });

    Future<http.Response> intento(String nombre, String h, {String? ip}) => enviar(
      'POST',
      '/v2/sesion',
      cuerpo: {
        'nombre': nombre,
        'huellaAcceso': h,
        'dispositivo': {'id': 'x', 'nombre': 'x'},
      },
      cabeceras: {'x-real-ip': ?ip},
    );

    test('contraseña incorrecta, usuario inexistente y usuario desactivado dan el mismo error', () async {
      await registrar('ana');
      await registrar('luis');
      almacen.desactivarUsuario(almacen.usuarioPorNombre('luis')!.id, true);
      final mala = await intento('ana', huellaMala, ip: '198.51.100.1');
      final inexistente = await intento('nadie', huella, ip: '198.51.100.2');
      final desactivado = await intento('luis', huella, ip: '198.51.100.3');
      expect(mala.statusCode, 401);
      expect(json(mala), json(inexistente));
      expect(json(mala), json(desactivado));
    });

    test('tras varios fallos desde la misma IP se bloquean los intentos', () async {
      await registrar('ana');
      for (var i = 0; i < 3; i++) {
        expect((await intento('ana', huellaMala, ip: '203.0.113.9')).statusCode, 401);
      }
      expect(
        (await intento('ana', huella, ip: '203.0.113.9')).statusCode,
        429,
        reason: 'Bloqueado incluso con la contraseña buena',
      );
    });

    test('revocar un dispositivo y cerrar sesión invalidan el token', () async {
      final token = await registrar('ana');
      final otro = json(await intento('ana', huella))['token'] as String;
      expect((await enviar('DELETE', '/v2/dispositivos/x', token: token)).statusCode, 204);
      expect(json(await enviar('GET', '/v2/yo', token: otro))['error'], 'sesion_invalida');
      expect((await enviar('DELETE', '/v2/sesion', token: token)).statusCode, 204);
      expect((await enviar('GET', '/v2/yo', token: token)).statusCode, 401);
    });

    test('desactivar un usuario corta sus sesiones al momento', () async {
      final token = await registrar('ana');
      almacen.desactivarUsuario(almacen.usuarioPorNombre('ana')!.id, true);
      expect((await enviar('GET', '/v2/yo', token: token)).statusCode, 401);
    });
  });

  group('Bóvedas y permisos', () {
    late String ana, luis, eva, boveda;

    setUp(() async {
      ana = await registrar('ana');
      luis = await registrar('luis');
      eva = await registrar('eva');
      boveda = await crearBoveda(ana);
    });

    test('quien crea la bóveda es propietario y recibe su copia de la clave', () async {
      final lista = json(await enviar('GET', '/v2/bovedas', token: ana))['bovedas'] as List;
      final b = lista.single as Map;
      expect(b['rol'], 'propietario');
      expect(b['claveBovedaCifrada'], b64('clave-para-propietario'));
      expect(b['nombreCifrado'], b64('Casa'));
    });

    test('quien no es miembro no ve la bóveda ni sabe que existe', () async {
      expect(json(await enviar('GET', '/v2/bovedas', token: luis))['bovedas'], isEmpty);
      final r = await enviar('GET', '/v2/bovedas/$boveda/cambios', token: luis);
      expect(r.statusCode, 404);
      expect(json(r)['error'], 'boveda_no_existe');
    });

    test('el propietario comparte con la clave pública del otro y cada uno recibe su copia', () async {
      final publica = await enviar('GET', '/v2/usuarios/luis/clave-publica', token: ana);
      expect(json(publica)['clavePublica'], b64('publica-luis'));
      expect((await compartir(ana, boveda, 'luis', 'escritura')).statusCode, 204);
      final suya = (json(await enviar('GET', '/v2/bovedas', token: luis))['bovedas'] as List).single as Map;
      expect(suya['rol'], 'escritura');
      expect(suya['claveBovedaCifrada'], b64('clave-para-luis'));
    });

    test('solo lectura puede consultar pero no escribir', () async {
      await compartir(ana, boveda, 'eva', 'lectura');
      await enviar(
        'POST',
        '/v2/bovedas/$boveda/cambios',
        token: ana,
        cuerpo: {
          'cambios': [b64('a')],
        },
      );
      final lee = await enviar('GET', '/v2/bovedas/$boveda/cambios', token: eva);
      expect((json(lee)['cambios'] as List).length, 1);
      final escribe = await enviar(
        'POST',
        '/v2/bovedas/$boveda/cambios',
        token: eva,
        cuerpo: {
          'cambios': [b64('b')],
        },
      );
      expect(escribe.statusCode, 403);
      expect(json(escribe)['error'], 'solo_lectura');
      final inst = await enviar(
        'PUT',
        '/v2/bovedas/$boveda/instantanea',
        token: eva,
        cuerpo: {'hasta': 0, 'datos': b64('x')},
      );
      expect(inst.statusCode, 403);
    });

    test('escritura puede apuntar pero no gestionar miembros ni borrar la bóveda', () async {
      await compartir(ana, boveda, 'luis', 'escritura');
      final sube = await enviar(
        'POST',
        '/v2/bovedas/$boveda/cambios',
        token: luis,
        cuerpo: {
          'cambios': [b64('a')],
        },
      );
      expect(sube.statusCode, 200);
      final invita = await compartir(luis, boveda, 'eva', 'lectura');
      expect(json(invita)['error'], 'solo_propietario');
      final borra = await enviar('DELETE', '/v2/bovedas/$boveda', token: luis, cuerpo: {'huellaAcceso': huella});
      expect(borra.statusCode, 403);
    });

    test('cambiar el rol no exige reenviar la clave, añadir sí', () async {
      expect(
        json(await compartir(ana, boveda, 'luis', 'lectura', conClave: false))['error'],
        'falta_claveBovedaCifrada',
      );
      await compartir(ana, boveda, 'luis', 'lectura');
      expect((await compartir(ana, boveda, 'luis', 'escritura', conClave: false)).statusCode, 204);
      final miembros = json(await enviar('GET', '/v2/bovedas/$boveda/miembros', token: luis))['miembros'] as List;
      expect(
        miembros,
        containsAll([
          {'usuario': 'ana', 'rol': 'propietario'},
          {'usuario': 'luis', 'rol': 'escritura'},
        ]),
      );
      expect(json(await compartir(ana, boveda, 'luis', 'jefe'))['error'], 'rol_invalido');
      expect((await compartir(ana, boveda, 'nadie', 'lectura')).statusCode, 404);
    });

    test('una bóveda nunca se queda sin propietario', () async {
      final baja = await compartir(ana, boveda, 'ana', 'lectura', conClave: false);
      expect(json(baja)['error'], 'ultimo_propietario');
      final sale = await enviar('DELETE', '/v2/bovedas/$boveda/miembros/ana', token: ana);
      expect(json(sale)['error'], 'ultimo_propietario');
      await compartir(ana, boveda, 'luis', 'propietario');
      expect((await enviar('DELETE', '/v2/bovedas/$boveda/miembros/ana', token: ana)).statusCode, 204);
    });

    test('un miembro puede salirse y pierde el acceso; solo el propietario echa a otros', () async {
      await compartir(ana, boveda, 'luis', 'escritura');
      await compartir(ana, boveda, 'eva', 'lectura');
      expect((await enviar('DELETE', '/v2/bovedas/$boveda/miembros/eva', token: luis)).statusCode, 403);
      expect((await enviar('DELETE', '/v2/bovedas/$boveda/miembros/luis', token: luis)).statusCode, 204);
      expect((await enviar('GET', '/v2/bovedas/$boveda/cambios', token: luis)).statusCode, 404);
      expect((await enviar('DELETE', '/v2/bovedas/$boveda/miembros/eva', token: ana)).statusCode, 204);
    });

    test('borrar la bóveda exige ser propietario y repetir la contraseña', () async {
      final mala = await enviar('DELETE', '/v2/bovedas/$boveda', token: ana, cuerpo: {'huellaAcceso': huellaMala});
      expect(mala.statusCode, 401);
      expect(
        (await enviar('DELETE', '/v2/bovedas/$boveda', token: ana, cuerpo: {'huellaAcceso': huella})).statusCode,
        204,
      );
      expect(almacen.boveda(boveda), isNull);
    });

    test('borrar la cuenta elimina las bóvedas que solo eran suyas y conserva las compartidas', () async {
      final compartida = await crearBoveda(ana);
      await compartir(ana, compartida, 'luis', 'propietario');
      expect((await enviar('DELETE', '/v2/yo', token: ana, cuerpo: {'huellaAcceso': huella})).statusCode, 204);
      expect(almacen.boveda(boveda), isNull);
      expect(almacen.boveda(compartida), isNotNull);
      expect(almacen.usuarioPorNombre('ana'), isNull);
    });
  });

  group('Cambios e instantáneas', () {
    late String token, boveda;

    setUp(() async {
      token = await registrar('ana');
      boveda = await crearBoveda(token);
    });

    test('los cambios se guardan en orden y se descargan por páginas', () async {
      final subida = await enviar(
        'POST',
        '/v2/bovedas/$boveda/cambios',
        token: token,
        cuerpo: {
          'cambios': [b64('a'), b64('b'), b64('c')],
        },
      );
      expect(subida.statusCode, 200);
      final secuencias = (json(subida)['secuencias'] as List).cast<int>();
      expect(secuencias, orderedEquals([...secuencias]..sort()));

      final pagina1 = json(await enviar('GET', '/v2/bovedas/$boveda/cambios?desde=0&limite=2', token: token));
      expect((pagina1['cambios'] as List).length, 2);
      expect(pagina1['hayMas'], isTrue);
      final ultimaVista = ((pagina1['cambios'] as List).last as Map)['secuencia'] as int;
      final pagina2 = json(await enviar('GET', '/v2/bovedas/$boveda/cambios?desde=$ultimaVista', token: token));
      expect(utf8.decode(base64.decode(((pagina2['cambios'] as List).single as Map)['datos'] as String)), 'c');
      expect(pagina2['hayMas'], isFalse);
      expect(pagina2['ultima'], secuencias.last);
    });

    test('cada bóveda solo contiene sus propios cambios', () async {
      final otra = await crearBoveda(token);
      await enviar(
        'POST',
        '/v2/bovedas/$boveda/cambios',
        token: token,
        cuerpo: {
          'cambios': [b64('secreto')],
        },
      );
      expect(json(await enviar('GET', '/v2/bovedas/$otra/cambios', token: token))['cambios'], isEmpty);
    });

    test('cambios vacíos o demasiados se rechazan', () async {
      final ruta = '/v2/bovedas/$boveda/cambios';
      expect((await enviar('POST', ruta, token: token, cuerpo: {'cambios': []})).statusCode, 400);
      final muchos = List.filled(501, b64('x'));
      expect((await enviar('POST', ruta, token: token, cuerpo: {'cambios': muchos})).statusCode, 413);
    });

    test('la instantánea compacta el historial y obliga a descargarla a quien va atrasado', () async {
      final sub = json(
        await enviar(
          'POST',
          '/v2/bovedas/$boveda/cambios',
          token: token,
          cuerpo: {
            'cambios': [b64('1'), b64('2'), b64('3')],
          },
        ),
      );
      final hasta = (sub['secuencias'] as List)[1] as int;
      final ruta = '/v2/bovedas/$boveda/instantanea';
      expect((await enviar('PUT', ruta, token: token, cuerpo: {'hasta': hasta, 'datos': b64('todo')})).statusCode, 204);

      final atrasado = await enviar('GET', '/v2/bovedas/$boveda/cambios?desde=0', token: token);
      expect(atrasado.statusCode, 409);
      expect(json(atrasado)['error'], 'instantanea_necesaria');

      expect(json(await enviar('GET', ruta, token: token))['hasta'], hasta);
      final resto = json(await enviar('GET', '/v2/bovedas/$boveda/cambios?desde=$hasta', token: token));
      expect((resto['cambios'] as List).length, 1);

      final antigua = await enviar('PUT', ruta, token: token, cuerpo: {'hasta': hasta - 1, 'datos': b64('x')});
      expect(antigua.statusCode, 409);
    });
  });

  group('Comandos', () {
    test('invitacion crear imprime un código usable', () async {
      final salida = StringBuffer();
      expect(await ejecutar(['invitacion', 'crear'], almacen: almacen, salida: salida), 0);
      final codigo = RegExp(r'[A-Z0-9]{4}(-[A-Z0-9]{4}){3}').firstMatch(salida.toString())!.group(0)!;
      expect(almacen.consumirInvitacion(codigo), isTrue);
    });

    test('usuarios y dispositivos: listar, revocar, desactivar y borrar', () async {
      await registrar('ana');
      final salida = StringBuffer();
      await ejecutar(['usuarios', 'listar'], almacen: almacen, salida: salida);
      await ejecutar(['dispositivos', 'listar', 'ana'], almacen: almacen, salida: salida);
      expect(salida.toString(), contains('Móvil de ana'));
      expect(await ejecutar(['dispositivos', 'revocar', 'ana', 'movil-ana'], almacen: almacen, salida: salida), 0);
      expect(await ejecutar(['dispositivos', 'revocar', 'ana', 'movil-ana'], almacen: almacen, salida: salida), 1);
      expect(await ejecutar(['usuarios', 'desactivar', 'ana'], almacen: almacen, salida: salida), 0);
      expect(almacen.usuarioPorNombre('ana')!.desactivado, isTrue);
      expect(await ejecutar(['usuarios', 'borrar', 'ana'], almacen: almacen, salida: salida), 0);
      expect(await ejecutar(['usuarios', 'borrar', 'ana'], almacen: almacen, salida: salida), 1);
    });

    test('un comando desconocido muestra la ayuda y devuelve 64', () async {
      final salida = StringBuffer();
      expect(await ejecutar(['otra', 'cosa'], almacen: almacen, salida: salida), 64);
      expect(salida.toString(), contains('invitacion crear'));
    });
  });

  group('Configuración y esquema', () {
    test('lee las variables de entorno con valores por defecto', () {
      final c = Configuracion.desdeEntorno({'PUERTO': '9000', 'TLS_CERTIFICADO': '/c.pem'});
      expect(c.puerto, 9000);
      expect(c.carpetaDatos, '/datos');
      expect(c.usaTlsPropio, isFalse, reason: 'Hace falta también la clave');
    });

    test('el limitador olvida los fallos pasada la ventana', () {
      var ahora = DateTime(2026);
      final l = LimitadorIntentos(maximo: 2, ventana: const Duration(minutes: 1), ahora: () => ahora);
      l.registrarFallo('ip');
      l.registrarFallo('ip');
      expect(l.bloqueado('ip'), isTrue);
      ahora = ahora.add(const Duration(minutes: 2));
      expect(l.bloqueado('ip'), isFalse);
    });

    test('una base de datos de la versión 0.1 se actualiza conservando sus tablas antiguas', () async {
      final carpeta = await Directory.systemTemp.createTemp('onbudget_v1');
      addTearDown(() => carpeta.delete(recursive: true));
      final ruta = '${carpeta.path}/onbudget.sqlite3';
      final v1 = sqlite3.open(ruta);
      v1.execute('''
        CREATE TABLE invitaciones(hash TEXT PRIMARY KEY, creada TEXT NOT NULL, usada TEXT);
        CREATE TABLE bovedas(id TEXT PRIMARY KEY, kdf TEXT NOT NULL, sal_acceso BLOB NOT NULL,
          hash_acceso TEXT NOT NULL, clave_cifrada BLOB NOT NULL, creada TEXT NOT NULL);
        CREATE TABLE dispositivos(id TEXT NOT NULL, boveda TEXT NOT NULL, nombre TEXT NOT NULL,
          hash_token TEXT NOT NULL UNIQUE, creado TEXT NOT NULL, ultimo_acceso TEXT,
          revocado INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (boveda, id));
        CREATE TABLE cambios(secuencia INTEGER PRIMARY KEY AUTOINCREMENT, boveda TEXT NOT NULL,
          dispositivo TEXT NOT NULL, datos BLOB NOT NULL, recibido TEXT NOT NULL);
        CREATE INDEX idx_cambios_boveda ON cambios(boveda, secuencia);
        CREATE TABLE instantaneas(boveda TEXT PRIMARY KEY, hasta INTEGER NOT NULL, dispositivo TEXT NOT NULL,
          datos BLOB NOT NULL, fecha TEXT NOT NULL);
        INSERT INTO bovedas VALUES ('vieja', '{}', x'00', 'h', x'00', '2026-11-09T00:00:00Z');
        PRAGMA user_version = 1;
      ''');
      v1.dispose();

      final a = Almacen.abrir(ruta);
      expect(a.bovedas(), isEmpty);
      expect(a.usuarios(), isEmpty);
      a.cerrar();
      final comprobacion = sqlite3.open(ruta);
      expect(comprobacion.select('SELECT id FROM bovedas_v1').single['id'], 'vieja');
      comprobacion.dispose();
    });
  });
}
