import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:onbudget_servidor/onbudget_servidor.dart';
import 'package:test/test.dart';

// Pruebas del panel /admin con el servidor real
void main() {
  late Almacen almacen;
  HttpServer? servidor;
  late Uri base;
  const contrasena = 'contraseña-de-prueba-larga';

  Future<void> arrancar({String? token}) async {
    almacen = Almacen.enMemoria();
    final config = Configuracion(direccion: '127.0.0.1', puerto: 0, intentosSesionPermitidos: 3, tokenAdmin: token);
    servidor = await servir(config, almacen, salida: StringBuffer());
    base = Uri.parse('http://127.0.0.1:${servidor!.port}');
  }

  tearDown(() async {
    if (servidor == null) return;
    await servidor!.close(force: true);
    servidor = null;
    almacen.cerrar();
  });

  Future<http.Response> pedir(
    String metodo,
    String ruta, {
    Map<String, String>? formulario,
    String? cookie,
    Map<String, String>? cabeceras,
  }) {
    final p = http.Request(metodo, base.resolve(ruta))..followRedirects = false;
    if (formulario != null) p.bodyFields = formulario;
    if (cookie != null) p.headers['cookie'] = cookie;
    if (cabeceras != null) p.headers.addAll(cabeceras);
    return p.send().then(http.Response.fromStream);
  }

  // Inicia sesión y devuelve la cookie y el token CSRF de la página de inicio
  Future<({String cookie, String csrf})> entrar() async {
    final r = await pedir('POST', '/admin/entrar', formulario: {'token': contrasena});
    expect(r.statusCode, 303);
    final cookie = r.headers['set-cookie']!.split(';').first;
    final inicio = await pedir('GET', '/admin', cookie: cookie);
    final csrf = RegExp(r'name="_csrf" value="([^"]+)"').firstMatch(inicio.body)!.group(1)!;
    return (cookie: cookie, csrf: csrf);
  }

  // Da de alta un usuario directamente en el almacén, como haría la app con una invitación
  Usuario alta(String nombre) => almacen.registrarUsuario(
    invitacion: almacen.crearInvitacion(),
    nombre: nombre,
    kdf: {'algoritmo': 'argon2id'},
    salAcceso: bytesAleatorios(16),
    hashAcceso: 'x',
    clavePublica: bytesAleatorios(32),
    clavePrivadaCifrada: bytesAleatorios(48),
  )!;

  group('Panel desactivado', () {
    setUp(() => arrancar());

    test('sin ADMIN_TOKEN el panel avisa y no deja entrar', () async {
      final r = await pedir('GET', '/admin');
      expect(r.statusCode, 503);
      expect(r.body, contains('ADMIN_TOKEN'));
      expect((await pedir('POST', '/admin/entrar', formulario: {'token': 'x'})).statusCode, 503);
    });

    test('la API sigue funcionando', () async {
      expect((await pedir('GET', '/salud')).statusCode, 200);
    });
  });

  group('Panel con ADMIN_TOKEN en hash', () {
    setUp(() => arrancar(token: hashTokenAdmin(contrasena, iteraciones: 1000)));

    test('sin sesión muestra el formulario de entrada con cabeceras de seguridad', () async {
      final r = await pedir('GET', '/admin');
      expect(r.statusCode, 200);
      expect(r.body, contains('type="password"'));
      expect(r.headers['content-security-policy'], contains("default-src 'none'"));
      expect(r.headers['x-frame-options'], 'DENY');
    });

    test('contraseña incorrecta no da sesión y se bloquea tras varios intentos', () async {
      for (var i = 0; i < 3; i++) {
        final r = await pedir('POST', '/admin/entrar', formulario: {'token': 'mala'});
        expect(r.statusCode, 401);
        expect(r.headers['set-cookie'], isNull);
      }
      final bloqueado = await pedir('POST', '/admin/entrar', formulario: {'token': contrasena});
      expect(bloqueado.statusCode, 429);
    });

    test('la cookie de sesión es HttpOnly y SameSite=Strict', () async {
      final r = await pedir('POST', '/admin/entrar', formulario: {'token': contrasena});
      final cookie = r.headers['set-cookie']!;
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Strict'));
      expect(cookie, contains('Path=/admin'));
      expect(cookie, isNot(contains('Secure')), reason: 'Sin HTTPS el navegador la descartaría');
      final conProxy = await pedir(
        'POST',
        '/admin/entrar',
        formulario: {'token': contrasena},
        cabeceras: {'x-forwarded-proto': 'https'},
      );
      expect(conProxy.headers['set-cookie'], contains('Secure'));
    });

    test('el resumen muestra las cifras del servidor', () async {
      almacen.crearInvitacion();
      final s = await entrar();
      final r = await pedir('GET', '/admin', cookie: s.cookie);
      expect(r.body, contains('Invitaciones sin usar'));
      expect(r.body, contains('Usuarios'));
      expect(r.body, isNot(contains('texto plano')), reason: 'El token está en hash');
    });

    test('crear una invitación muestra el código una vez y funciona en la app', () async {
      final s = await entrar();
      final r = await pedir('POST', '/admin/invitaciones/crear', cookie: s.cookie, formulario: {'_csrf': s.csrf});
      expect(r.statusCode, 200);
      final codigo = RegExp(r'[A-Z0-9]{4}(-[A-Z0-9]{4}){3}').firstMatch(r.body)!.group(0)!;
      expect(almacen.invitacionesSinUsar(), hasLength(1));
      final lista = await pedir('GET', '/admin/invitaciones', cookie: s.cookie);
      expect(lista.body, isNot(contains(codigo)), reason: 'El código no se puede volver a ver');
      expect(almacen.consumirInvitacion(codigo), isTrue);
    });

    test('anular una invitación concreta y todas', () async {
      final s = await entrar();
      almacen.crearInvitacion();
      almacen.crearInvitacion();
      final id = almacen.invitacionesSinUsar().first.id;
      await pedir('POST', '/admin/invitaciones/anular', cookie: s.cookie, formulario: {'_csrf': s.csrf, 'id': id});
      expect(almacen.invitacionesSinUsar(), hasLength(1));
      await pedir('POST', '/admin/invitaciones/anular', cookie: s.cookie, formulario: {'_csrf': s.csrf, 'id': 'todas'});
      expect(almacen.invitacionesSinUsar(), isEmpty);
    });

    test('sin el token CSRF no se ejecuta ninguna acción', () async {
      final s = await entrar();
      final r = await pedir('POST', '/admin/invitaciones/crear', cookie: s.cookie, formulario: {'_csrf': 'falso'});
      expect(r.statusCode, 303);
      expect(almacen.invitacionesSinUsar(), isEmpty);
    });

    test('usuarios: ver, revocar dispositivo, desactivar y borrar con confirmación', () async {
      final s = await entrar();
      final u = alta('ana');
      almacen.abrirSesion(u.id, 'movil', '<script>Móvil</script>');

      final lista = await pedir('GET', '/admin/usuarios', cookie: s.cookie);
      expect(lista.body, contains('ana'));
      final detalle = await pedir('GET', '/admin/usuarios/${u.id}', cookie: s.cookie);
      expect(detalle.body, contains('&lt;script&gt;'), reason: 'Los nombres se escapan');
      expect(detalle.body, isNot(contains('<script>')));

      await pedir(
        'POST',
        '/admin/usuarios/${u.id}/revocar',
        cookie: s.cookie,
        formulario: {'_csrf': s.csrf, 'dispositivo': 'movil'},
      );
      expect(almacen.dispositivos(u.id).single.revocado, isTrue);

      final token = almacen.abrirSesion(u.id, 'tablet', 'Tablet');
      await pedir(
        'POST',
        '/admin/usuarios/${u.id}/estado',
        cookie: s.cookie,
        formulario: {'_csrf': s.csrf, 'desactivar': 'si'},
      );
      expect(almacen.usuario(u.id)!.desactivado, isTrue);
      expect(almacen.dispositivoPorToken(token), isNull, reason: 'Desactivar cierra las sesiones');
      await pedir(
        'POST',
        '/admin/usuarios/${u.id}/estado',
        cookie: s.cookie,
        formulario: {'_csrf': s.csrf, 'desactivar': 'no'},
      );
      expect(almacen.usuario(u.id)!.desactivado, isFalse);

      await pedir('POST', '/admin/usuarios/${u.id}/borrar', cookie: s.cookie, formulario: {'_csrf': s.csrf});
      expect(almacen.usuario(u.id), isNotNull, reason: 'Sin la casilla de confirmación no se borra');
      await pedir(
        'POST',
        '/admin/usuarios/${u.id}/borrar',
        cookie: s.cookie,
        formulario: {'_csrf': s.csrf, 'confirmar': 'si'},
      );
      expect(almacen.usuario(u.id), isNull);
      expect((await pedir('GET', '/admin/usuarios/${u.id}', cookie: s.cookie)).statusCode, 404);
    });

    test('bóvedas: ver miembros con su permiso y borrar con confirmación', () async {
      final s = await entrar();
      final ana = alta('ana');
      final luis = alta('luis');
      final b = almacen.crearBoveda(ana.id, bytesAleatorios(16), bytesAleatorios(32));
      almacen.guardarMiembro(b.id, luis.id, Rol.lectura, bytesAleatorios(32));

      final lista = await pedir('GET', '/admin/bovedas', cookie: s.cookie);
      expect(lista.body, contains(b.id));
      final detalle = await pedir('GET', '/admin/bovedas/${b.id}', cookie: s.cookie);
      expect(detalle.body, contains('ana'));
      expect(detalle.body, contains('luis'));
      expect(detalle.body, contains('Solo consulta'));

      await pedir('POST', '/admin/bovedas/${b.id}/borrar', cookie: s.cookie, formulario: {'_csrf': s.csrf});
      expect(almacen.boveda(b.id), isNotNull, reason: 'Sin la casilla de confirmación no se borra');
      await pedir(
        'POST',
        '/admin/bovedas/${b.id}/borrar',
        cookie: s.cookie,
        formulario: {'_csrf': s.csrf, 'confirmar': 'si'},
      );
      expect(almacen.boveda(b.id), isNull);
      expect(almacen.usuario(ana.id), isNotNull, reason: 'Borrar la bóveda no borra a sus miembros');
    });

    test('salir invalida la sesión', () async {
      final s = await entrar();
      await pedir('POST', '/admin/salir', cookie: s.cookie, formulario: {'_csrf': s.csrf});
      final r = await pedir('GET', '/admin/bovedas', cookie: s.cookie);
      expect(r.statusCode, 303);
    });

    test('el idioma se elige con Accept-Language o ?idioma= y se recuerda', () async {
      final en = await pedir('GET', '/admin', cabeceras: {'accept-language': 'en-GB,en;q=0.9'});
      expect(en.body, contains('Admin password'));
      final de = await pedir('GET', '/admin?idioma=de');
      expect(de.body, contains('Administratorpasswort'));
      final cookie = de.headers['set-cookie']!.split(';').first;
      final recordado = await pedir('GET', '/admin', cookie: cookie);
      expect(recordado.body, contains('Administratorpasswort'));
    });

    test('el tema claro u oscuro se elige con ?tema= y se recuerda', () async {
      final oscuro = await pedir('GET', '/admin?tema=oscuro');
      expect(oscuro.body, contains('data-tema="oscuro"'));
      final cookie = oscuro.headers['set-cookie']!.split(';').first;
      expect((await pedir('GET', '/admin', cookie: cookie)).body, contains('data-tema="oscuro"'));
      final sistema = await pedir('GET', '/admin?tema=sistema', cookie: cookie);
      expect(sistema.body, isNot(contains('data-tema=')), reason: 'Automático sigue al sistema');
      expect(sistema.headers['set-cookie'], contains('Max-Age=0'));
    });

    test('tras cada acción se confirma con un mensaje, solo con claves conocidas', () async {
      final s = await entrar();
      almacen.crearInvitacion();
      final r = await pedir(
        'POST',
        '/admin/invitaciones/anular',
        cookie: s.cookie,
        formulario: {'_csrf': s.csrf, 'id': 'todas'},
      );
      expect(r.headers['location'], '/admin/invitaciones?ok=invitacionesAnuladas');
      final pagina = await pedir('GET', r.headers['location']!, cookie: s.cookie);
      expect(pagina.body, contains('Invitaciones anuladas.'));
      final inventado = await pedir('GET', '/admin/invitaciones?ok=%3Cscript%3E', cookie: s.cookie);
      expect(inventado.body, isNot(contains('mensaje exito')));
    });

    test('el texto de borrar usuario concuerda con sus bóvedas propias', () async {
      final s = await entrar();
      final ana = alta('ana');
      final sinBovedas = await pedir('GET', '/admin/usuarios/${ana.id}', cookie: s.cookie);
      expect(sinBovedas.body, contains('Entiendo que se borrará el usuario y que no se puede deshacer.'));
      expect(sinBovedas.body, isNot(contains('las 0 bóvedas')));
    });

    test('la hoja de estilos, el logo y el script se sirven sin sesión', () async {
      final logo = await pedir('GET', '/admin/logo.png');
      expect(logo.statusCode, 200);
      expect(logo.headers['content-type'], 'image/png');
      expect(logo.bodyBytes.take(4), [0x89, 0x50, 0x4E, 0x47], reason: 'Cabecera PNG');
      final script = await pedir('GET', '/admin/copiar.js');
      expect(script.statusCode, 200);
      expect(script.headers['content-type'], startsWith('text/javascript'));
      final pagina = await pedir('GET', '/admin');
      expect(pagina.headers['content-security-policy'], contains("script-src 'self'"));
      expect(pagina.headers['content-security-policy'], isNot(contains('unsafe-inline')));
    });

    test('la hoja de estilos se sirve sin sesión', () async {
      final r = await pedir('GET', '/admin/estilos.css');
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], startsWith('text/css'));
    });
  });

  group('ADMIN_TOKEN', () {
    test('en texto plano funciona pero el panel avisa', () async {
      await arrancar(token: contrasena);
      final s = await entrar();
      final r = await pedir('GET', '/admin', cookie: s.cookie);
      expect(r.body, contains('texto plano'));
    });

    test('hash: acepta la contraseña buena y rechaza el resto', () {
      final hash = hashTokenAdmin('una-contraseña', iteraciones: 1000);
      expect(tokenAdminEsHash(hash), isTrue);
      expect(comprobarTokenAdmin('una-contraseña', hash), isTrue);
      expect(comprobarTokenAdmin('otra', hash), isFalse);
      expect(comprobarTokenAdmin('x', r'$pbkdf2-sha256$roto'), isFalse);
    });

    test('PBKDF2-SHA256 coincide con el vector de prueba del RFC 7914', () {
      final r = pbkdf2Sha256('passwd'.codeUnits, 'salt'.codeUnits, 1, 64);
      final hex = r.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex.substring(0, 32), '55ac046e56e3089fec1691c22544b605');
    });

    test('el comando admin hash rechaza contraseñas cortas', () async {
      await arrancar();
      final salida = StringBuffer();
      expect(await ejecutar(['admin', 'hash', 'corta'], almacen: almacen, salida: salida), 1);
      expect(await ejecutar(['admin', 'hash', 'una-contraseña-larga'], almacen: almacen, salida: salida), 0);
      expect(salida.toString(), contains(r'$pbkdf2-sha256$'));
    });
  });

  group('fechas del panel', () {
    final ahora = DateTime(2026, 11, 17, 23, 0);

    test('formato propio de cada idioma', () {
      final f = DateTime(2026, 11, 10, 22, 7);
      expect(fechaLegible(f, 'es'), '10 nov 2026, 22:07');
      expect(fechaLegible(f, 'en'), '10 Nov 2026, 22:07');
      expect(fechaLegible(f, 'de'), '10. Nov. 2026, 22:07');
      expect(fechaLegible(DateTime(2026, 8, 3, 9, 5), 'fr'), '3 août 2026, 09:05');
    });

    test('relativa durante la última semana; después, null', () {
      expect(fechaRelativa(ahora.subtract(const Duration(seconds: 20)), ahora, 'es'), 'Hace un momento');
      expect(fechaRelativa(ahora.subtract(const Duration(minutes: 5)), ahora, 'es'), 'Hace 5 min');
      expect(fechaRelativa(ahora.subtract(const Duration(hours: 3)), ahora, 'en'), '3 h ago');
      expect(fechaRelativa(ahora.subtract(const Duration(hours: 30)), ahora, 'es'), 'Ayer');
      expect(fechaRelativa(ahora.subtract(const Duration(days: 4)), ahora, 'de'), 'Vor 4 Tagen');
      expect(fechaRelativa(ahora.subtract(const Duration(days: 8)), ahora, 'es'), isNull);
      expect(fechaRelativa(ahora.add(const Duration(minutes: 1)), ahora, 'es'), isNull, reason: 'Reloj adelantado');
    });

    test('cada idioma tiene los 12 meses', () {
      for (final idioma in idiomasPanel) {
        expect(texto(idioma, 'meses').split(','), hasLength(12), reason: idioma);
      }
    });
  });

  test('textos del panel: los 4 idiomas tienen las mismas claves', () {
    final claves = textosPanel['es']!.keys.toSet();
    for (final idioma in idiomasPanel) {
      expect(textosPanel[idioma]!.keys.toSet(), claves, reason: idioma);
    }
  });
}
