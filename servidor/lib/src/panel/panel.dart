import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../almacen.dart';
import '../configuracion.dart';
import '../limitador.dart';
import '../seguridad.dart';
import '../token_admin.dart';
import 'estilos.dart';
import 'logo.dart';
import 'script.dart';
import 'textos.dart';

const String _cookieSesion = 'onbudget_admin';
const String _cookieIdioma = 'onbudget_idioma';
const String _cookieTema = 'onbudget_tema';
const List<String> _temas = ['claro', 'oscuro'];
const String _base = '/admin';

class _SesionAdmin {
  final String csrf;
  DateTime caduca;
  _SesionAdmin(this.csrf, this.caduca);
}

// Panel web de administración (/admin), al estilo del de Vaultwarden.
// HTML servido por el propio servidor, sin dependencias externas; solo un JS mínimo propio para copiar.
class PanelAdmin {
  final Almacen almacen;
  final Configuracion config;
  final String cabeceraIp;
  final DateTime Function() ahora;
  final LimitadorIntentos _limitador;
  final Map<String, _SesionAdmin> _sesiones = {};

  PanelAdmin(this.almacen, this.config, {this.cabeceraIp = 'x-real-ip', DateTime Function()? ahora})
    : ahora = ahora ?? DateTime.now,
      _limitador = LimitadorIntentos(
        maximo: config.intentosSesionPermitidos,
        ventana: config.ventanaIntentosSesion,
        ahora: ahora,
      );

  Handler get handler {
    final r = Router()
      ..get('$_base/estilos.css', _estilos)
      ..get('$_base/copiar.js', _script)
      ..get('$_base/logo.png', _logo)
      ..get(_base, _inicio)
      ..get('$_base/', _inicio)
      ..post('$_base/entrar', _entrar)
      ..post('$_base/salir', _conSesion(_salir))
      ..get('$_base/invitaciones', _conSesion(_invitaciones))
      ..post('$_base/invitaciones/crear', _conSesion(_crearInvitacion))
      ..post('$_base/invitaciones/anular', _conSesion(_anularInvitacion))
      ..get('$_base/bovedas', _conSesion(_bovedas))
      ..get('$_base/bovedas/<id>', _conSesionId(_boveda))
      ..post('$_base/bovedas/<id>/borrar', _conSesionId(_borrarBoveda))
      ..get('$_base/usuarios', _conSesion(_usuarios))
      ..get('$_base/usuarios/<id>', _conSesionId(_usuario))
      ..post('$_base/usuarios/<id>/estado', _conSesionId(_cambiarEstadoUsuario))
      ..post('$_base/usuarios/<id>/borrar', _conSesionId(_borrarUsuario))
      ..post('$_base/usuarios/<id>/revocar', _conSesionId(_revocarDispositivo));
    return r.call;
  }

  // --- Sesión, idioma y seguridad ---

  String _idioma(Request r) {
    final pedido = r.url.queryParameters['idioma'];
    if (pedido != null && idiomasPanel.contains(pedido)) return pedido;
    final cookie = _cookies(r)[_cookieIdioma];
    if (cookie != null && idiomasPanel.contains(cookie)) return cookie;
    for (final parte in (r.headers['accept-language'] ?? '').split(',')) {
      final codigo = parte.trim().split(RegExp('[-;_]')).first.toLowerCase();
      if (idiomasPanel.contains(codigo)) return codigo;
    }
    return idiomaPorDefecto;
  }

  // Tema elegido a mano (claro u oscuro); null = el del sistema
  String? _tema(Request r) {
    final pedido = r.url.queryParameters['tema'];
    if (pedido != null) return _temas.contains(pedido) ? pedido : null;
    final cookie = _cookies(r)[_cookieTema];
    return _temas.contains(cookie) ? cookie : null;
  }

  static Map<String, String> _cookies(Request r) {
    final resultado = <String, String>{};
    for (final c in (r.headers['cookie'] ?? '').split(';')) {
      final i = c.indexOf('=');
      if (i > 0) resultado[c.substring(0, i).trim()] = c.substring(i + 1).trim();
    }
    return resultado;
  }

  bool _esHttps(Request r) =>
      r.requestedUri.scheme == 'https' ||
      config.usaTlsPropio ||
      (r.headers['x-forwarded-proto'] ?? '').toLowerCase() == 'https';

  String _cookie(Request r, String nombre, String valor, {Duration? duracion}) {
    final partes = [
      '$nombre=$valor',
      'Path=$_base',
      'HttpOnly',
      'SameSite=Strict',
      if (_esHttps(r)) 'Secure',
      if (duracion != null) 'Max-Age=${duracion.inSeconds}',
    ];
    return partes.join('; ');
  }

  _SesionAdmin? _sesion(Request r) {
    final token = _cookies(r)[_cookieSesion];
    if (token == null) return null;
    final clave = hashDe(token);
    final s = _sesiones[clave];
    if (s == null) return null;
    if (ahora().isAfter(s.caduca)) {
      _sesiones.remove(clave);
      return null;
    }
    // Caducidad deslizante: cada petición alarga la sesión
    s.caduca = ahora().add(config.duracionSesionAdmin);
    return s;
  }

  String _ip(Request r) {
    final cabecera = r.headers[cabeceraIp];
    if (cabecera != null && cabecera.isNotEmpty) return cabecera.split(',').first.trim();
    final info = r.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'desconocida';
  }

  static Future<Map<String, String>> _formulario(Request r) async {
    final cuerpo = await r.readAsString();
    if (cuerpo.length > 4096) return const {};
    try {
      return Uri.splitQueryString(cuerpo);
    } on FormatException {
      return const {};
    }
  }

  Handler _conSesion(Future<Response> Function(Request, _SesionAdmin, String idioma) accion) => (r) async {
    if (!config.panelActivo) return _desactivado(r);
    final s = _sesion(r);
    if (s == null) return _redirigir('$_base?caducada=1');
    if (r.method == 'POST') {
      final form = await _formulario(r);
      // Defensa contra CSRF además de SameSite=Strict
      if (!igualesSeguro(form['_csrf'] ?? '', s.csrf)) return _redirigir('$_base?caducada=1');
      return accion(r.change(context: {'formulario': form}), s, _idioma(r));
    }
    return accion(r, s, _idioma(r));
  };

  Handler _conSesionId(Future<Response> Function(Request, _SesionAdmin, String idioma, String id) accion) =>
      (Request r) => _conSesion((r2, s, i) => accion(r2, s, i, r.params['id'] ?? ''))(r);

  static Map<String, String> _form(Request r) => (r.context['formulario'] as Map<String, String>?) ?? const {};

  Response _redirigir(String a, {Map<String, String>? cabeceras}) => Response.seeOther(a, headers: {...?cabeceras});

  // --- HTML ---

  static String esc(Object? v) => const HtmlEscape().convert('${v ?? ''}');

  static String _mensaje(String tipo, String texto) => '<div class="mensaje $tipo">${esc(texto)}</div>';

  String _csrfCampo(_SesionAdmin s) => '<input type="hidden" name="_csrf" value="${esc(s.csrf)}">';

  // Fecha en el formato del idioma; si es de la última semana, relativa ("Hace 2 h") con la exacta al pasar el ratón
  String _fecha(DateTime? f, String idioma) {
    if (f == null) return esc(texto(idioma, 'nunca'));
    final exacta = fechaLegible(f.toLocal(), idioma);
    final relativa = fechaRelativa(f, ahora(), idioma);
    final iso = esc(f.toUtc().toIso8601String());
    if (relativa == null) return '<time datetime="$iso">${esc(exacta)}</time>';
    return '<time datetime="$iso" title="${esc(exacta)}">${esc(relativa)}</time>';
  }

  // Los UUID completos dominan las tablas: se muestran 8 caracteres y el resto al pasar el ratón (los cortos, enteros)
  static String _idCorto(String id) =>
      '<span class="id-corto" title="${esc(id)}">${esc(id.length > 12 ? '${id.substring(0, 8)}…' : id)}</span>';

  static String _chip(bool activo, String etiqueta) =>
      '<span class="chip ${activo ? 'activo' : 'inactivo'}">${esc(etiqueta)}</span>';

  // Estado vacío: icono, explicación y, si procede, la acción que lo resuelve
  static String _vacio(String icono, String mensaje, {String accion = ''}) =>
      '<div class="tarjeta vacio"><div class="icono" aria-hidden="true">$icono</div><p>${esc(mensaje)}</p>$accion</div>';

  // Mensaje de confirmación tras una acción (?ok=clave). Solo claves conocidas, nunca texto de la URL
  static const List<String> _confirmaciones = [
    'invitacionAnulada',
    'invitacionesAnuladas',
    'usuarioDesactivado',
    'usuarioActivado',
    'usuarioBorrado',
    'bovedaBorrada',
    'dispositivoDesconectado',
  ];

  String _confirmacion(Request r, String idioma) {
    final ok = r.url.queryParameters['ok'];
    return ok != null && _confirmaciones.contains(ok) ? _mensaje('exito', texto(idioma, 'ok_$ok')) : '';
  }

  static String _nombreArchivo(String ruta) => ruta.split(RegExp(r'[/\\]')).last;

  static String _tamano(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Response _pagina(Request r, String idioma, _SesionAdmin? s, String activa, String contenido, {int estado = 200}) {
    String enlace(String ruta, String clave) =>
        '<a href="$_base$ruta"${activa == clave ? ' aria-current="page"' : ''}>${esc(texto(idioma, clave))}</a>';
    final menu = s == null
        ? ''
        : '<nav aria-label="${esc(texto(idioma, 'menu'))}">'
              '${enlace('', 'resumen')}${enlace('/usuarios', 'usuarios')}${enlace('/invitaciones', 'invitaciones')}${enlace('/bovedas', 'bovedas')}'
              '<form class="linea" method="post" action="$_base/salir">${_csrfCampo(s)}'
              '<button class="enlace" type="submit">${esc(texto(idioma, 'salir'))}</button></form></nav>';
    final idiomas = idiomasPanel
        .map(
          (i) => i == idioma
              ? '<strong aria-current="true">${i.toUpperCase()}</strong>'
              : '<a href="?idioma=$i" hreflang="$i" lang="$i">${i.toUpperCase()}</a>',
        )
        .join('');
    final tema = _tema(r);
    String opcionTema(String? valor, String clave) => valor == tema
        ? '<strong aria-current="true">${esc(texto(idioma, clave))}</strong>'
        : '<a href="?tema=${valor ?? 'sistema'}">${esc(texto(idioma, clave))}</a>';
    final temas =
        '${opcionTema(null, 'temaSistema')}${opcionTema('claro', 'temaClaro')}${opcionTema('oscuro', 'temaOscuro')}';
    final html =
        '''<!doctype html>
<html lang="$idioma"${tema == null ? '' : ' data-tema="$tema"'}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#147AA3">
<title>On Budget · ${esc(texto(idioma, 'titulo'))}</title>
<link rel="icon" type="image/png" href="$_base/logo.png">
<link rel="stylesheet" href="$_base/estilos.css">
<script src="$_base/copiar.js" defer></script>
</head>
<body>
<header><a class="marca" href="$_base"><img src="$_base/logo.png" alt="" width="32" height="32">On Budget · ${esc(texto(idioma, 'titulo'))}</a>$menu</header>
<main>$contenido</main>
<footer>
<span class="grupo" aria-label="${esc(texto(idioma, 'idioma'))}">$idiomas</span>·<span class="grupo" aria-label="${esc(texto(idioma, 'tema'))}">$temas</span>· v${Configuracion.versionServidor}
</footer>
</body>
</html>''';
    final cabeceras = <String, Object>{
      'content-type': 'text/html; charset=utf-8',
      'content-security-policy':
          "default-src 'none'; style-src 'self'; script-src 'self'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      'x-frame-options': 'DENY',
    };
    // Recordar el idioma (?idioma=) y el tema (?tema=) elegidos
    final galletas = <String>[
      if (r.url.queryParameters.containsKey('idioma'))
        _cookie(r, _cookieIdioma, idioma, duracion: const Duration(days: 365)),
      if (r.url.queryParameters.containsKey('tema'))
        tema == null
            ? _cookie(r, _cookieTema, '', duracion: Duration.zero)
            : _cookie(r, _cookieTema, tema, duracion: const Duration(days: 365)),
    ];
    if (galletas.isNotEmpty) cabeceras['set-cookie'] = galletas;
    return Response(estado, body: html, headers: cabeceras);
  }

  // --- Páginas ---

  Response _desactivado(Request r) {
    final idioma = _idioma(r);
    return _pagina(r, idioma, null, '', _mensaje('aviso', texto(idioma, 'desactivado')), estado: 503);
  }

  Response _estilos(Request r) =>
      Response.ok(estilosPanel, headers: {'content-type': 'text/css; charset=utf-8', 'cache-control': 'max-age=3600'});

  Response _script(Request r) => Response.ok(
    scriptCopiar,
    headers: {'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'max-age=3600'},
  );

  static final List<int> _logoBytes = base64Decode(logoPanelBase64);

  Response _logo(Request r) =>
      Response.ok(_logoBytes, headers: {'content-type': 'image/png', 'cache-control': 'max-age=86400'});

  Future<Response> _inicio(Request r) async {
    final idioma = _idioma(r);
    if (!config.panelActivo) return _desactivado(r);
    final s = _sesion(r);
    if (s == null) return _paginaEntrada(r, idioma, caducada: r.url.queryParameters['caducada'] == '1');

    final c = almacen.resumen();
    String cifra(Object valor, String clave) =>
        '<div class="cifra"><div class="valor">${esc(valor)}</div><div class="etiqueta">${esc(texto(idioma, clave))}</div></div>';
    final avisos = StringBuffer();
    if (!tokenAdminEsHash(config.tokenAdmin!)) avisos.write(_mensaje('aviso', texto(idioma, 'avisoTextoPlano')));
    final contenido =
        '''
<h1>${esc(texto(idioma, 'resumen'))}</h1>
$avisos
<div class="cifras">
${cifra(c.usuarios, 'usuarios')}
${cifra(c.bovedas, 'bovedas')}
${cifra(c.dispositivosActivos, 'dispositivosActivos')}
${cifra(c.cambios, 'cambiosGuardados')}
${cifra(c.invitaciones, 'invitacionesPendientes')}
</div>
<div class="tarjeta tabla separada">
<table>
<tr><th scope="row">${esc(texto(idioma, 'version'))}</th><td>${Configuracion.versionServidor} (API ${Configuracion.versionApi})</td></tr>
<tr><th scope="row">${esc(texto(idioma, 'https'))}</th><td>${esc(texto(idioma, config.usaTlsPropio ? 'httpsPropio' : 'httpsProxy'))}</td></tr>
<tr><th scope="row">${esc(texto(idioma, 'baseDatos'))}</th><td><code>${esc(_nombreArchivo(config.rutaBaseDatos))}</code> · ${_tamano(almacen.tamanoBytes())}
<details><summary>${esc(texto(idioma, 'rutaCompleta'))}</summary><code>${esc(config.rutaBaseDatos)}</code></details></td></tr>
</table>
</div>
<p class="suave">${esc(texto(idioma, 'avisoCifrado'))}</p>''';
    return _pagina(r, idioma, s, 'resumen', contenido);
  }

  Response _paginaEntrada(Request r, String idioma, {String? error, bool caducada = false, int estado = 200}) {
    final avisos = StringBuffer();
    if (error != null) avisos.write(_mensaje('error', error));
    if (caducada) avisos.write(_mensaje('aviso', texto(idioma, 'sesionCaducada')));
    if (!_esHttps(r) && !_esLocal(r)) avisos.write(_mensaje('aviso', texto(idioma, 'avisoSinHttps')));
    final contenido =
        '''
<div class="entrada tarjeta">
<img src="$_base/logo.png" alt="" width="72" height="72">
<h1>On Budget</h1>
<p class="suave">${esc(texto(idioma, 'titulo'))}</p>
$avisos
<form method="post" action="$_base/entrar">
<label for="token">${esc(texto(idioma, 'contrasena'))}</label>
<input id="token" name="token" type="password" autocomplete="current-password" aria-describedby="ayuda-token" required autofocus>
<p class="ayuda" id="ayuda-token">${esc(texto(idioma, 'ayudaContrasena'))}</p>
<button type="submit">${esc(texto(idioma, 'entrar'))}</button>
</form>
</div>''';
    return _pagina(r, idioma, null, '', contenido, estado: estado);
  }

  bool _esLocal(Request r) {
    final host = r.requestedUri.host;
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  Future<Response> _entrar(Request r) async {
    final idioma = _idioma(r);
    if (!config.panelActivo) return _desactivado(r);
    final ip = _ip(r);
    if (_limitador.bloqueado(ip)) {
      return _paginaEntrada(r, idioma, error: texto(idioma, 'demasiadosIntentos'), estado: 429);
    }
    final form = await _formulario(r);
    if (!comprobarTokenAdmin(form['token'] ?? '', config.tokenAdmin!)) {
      _limitador.registrarFallo(ip);
      return _paginaEntrada(r, idioma, error: texto(idioma, 'credencialesIncorrectas'), estado: 401);
    }
    _limitador.limpiar(ip);
    final token = nuevoToken();
    _sesiones.removeWhere((_, s) => ahora().isAfter(s.caduca));
    _sesiones[hashDe(token)] = _SesionAdmin(nuevoToken(), ahora().add(config.duracionSesionAdmin));
    return _redirigir(_base, cabeceras: {'set-cookie': _cookie(r, _cookieSesion, token)});
  }

  Future<Response> _salir(Request r, _SesionAdmin s, String idioma) async {
    _sesiones.removeWhere((_, x) => identical(x, s));
    return _redirigir(_base, cabeceras: {'set-cookie': _cookie(r, _cookieSesion, '', duracion: Duration.zero)});
  }

  Future<Response> _invitaciones(Request r, _SesionAdmin s, String idioma, {String? codigoNuevo, String? aviso}) async {
    final lista = almacen.invitacionesSinUsar();
    final filas = lista
        .map(
          (i) =>
              '<tr><td><code>${esc(i.id)}</code></td><td>${_fecha(i.creada, idioma)}</td><td class="accion">'
              '<form class="linea" method="post" action="$_base/invitaciones/anular">${_csrfCampo(s)}'
              '<input type="hidden" name="id" value="${esc(i.id)}">'
              '<button class="secundario" type="submit">${esc(texto(idioma, 'anular'))}</button></form></td></tr>',
        )
        .join('\n');
    final nuevo = codigoNuevo == null
        ? ''
        : '<div class="tarjeta"><p>${esc(texto(idioma, 'codigoCreado'))}</p>'
              '<span class="codigo-grande" id="codigo-nuevo">${esc(codigoNuevo)}</span>'
              '<div class="fila-acciones"><button class="secundario" type="button" data-copiar="codigo-nuevo" '
              'data-copiado="${esc(texto(idioma, 'copiado'))}" hidden>${esc(texto(idioma, 'copiar'))}</button></div>'
              '<p class="suave">${esc(texto(idioma, 'codigoUso'))}</p></div>';
    final contenido =
        '''
<h1>${esc(texto(idioma, 'invitaciones'))}</h1>
${aviso ?? _confirmacion(r, idioma)}
$nuevo
<form method="post" action="$_base/invitaciones/crear">${_csrfCampo(s)}
<button type="submit">${esc(texto(idioma, 'crearInvitacion'))}</button>
</form>
<h2>${esc(texto(idioma, 'invitacionesPendientes'))}</h2>
${lista.isEmpty ? _vacio('✉', texto(idioma, 'sinInvitaciones')) : '''
<div class="tarjeta tabla"><table>
<tr><th scope="col">ID</th><th scope="col">${esc(texto(idioma, 'creada'))}</th><th></th></tr>
$filas
</table></div>
<form method="post" action="$_base/invitaciones/anular">${_csrfCampo(s)}
<input type="hidden" name="id" value="todas">
<button class="secundario" type="submit">${esc(texto(idioma, 'anularTodas'))}</button>
</form>'''}''';
    return _pagina(r, idioma, s, 'invitaciones', contenido);
  }

  Future<Response> _crearInvitacion(Request r, _SesionAdmin s, String idioma) =>
      // Se muestra directamente (no por redirección) para que el código no quede en ninguna URL
      _invitaciones(r, s, idioma, codigoNuevo: almacen.crearInvitacion());

  Future<Response> _anularInvitacion(Request r, _SesionAdmin s, String idioma) async {
    final id = _form(r)['id'] ?? '';
    if (id == 'todas') {
      almacen.anularInvitaciones();
      return _redirigir('$_base/invitaciones?ok=invitacionesAnuladas');
    } else if (!almacen.anularInvitacion(id)) {
      return _invitaciones(r, s, idioma, aviso: _mensaje('error', texto(idioma, 'noEncontrado')));
    }
    return _redirigir('$_base/invitaciones?ok=invitacionAnulada');
  }

  Future<Response> _bovedas(Request r, _SesionAdmin s, String idioma) async {
    final lista = almacen.bovedas();
    final filas = lista
        .map(
          (b) =>
              '<tr><td><a href="$_base/bovedas/${Uri.encodeComponent(b.id)}">${_idCorto(b.id)}</a></td><td>${_fecha(b.creada, idioma)}</td>'
              '<td>${b.miembros}</td><td>${b.cambios}</td>'
              '<td class="accion"><a href="$_base/bovedas/${Uri.encodeComponent(b.id)}">${esc(texto(idioma, 'ver'))}</a></td></tr>',
        )
        .join('\n');
    final tabla = lista.isEmpty
        ? _vacio('▣', texto(idioma, 'sinBovedas'))
        : '<div class="tarjeta tabla"><table>'
              '<tr><th scope="col">${esc(texto(idioma, 'boveda'))}</th><th scope="col">${esc(texto(idioma, 'creada'))}</th>'
              '<th scope="col">${esc(texto(idioma, 'miembros'))}</th><th scope="col">${esc(texto(idioma, 'cambios'))}</th><th></th></tr>'
              '$filas</table></div>';
    return _pagina(
      r,
      idioma,
      s,
      'bovedas',
      '<h1>${esc(texto(idioma, 'bovedas'))}</h1>${_confirmacion(r, idioma)}$tabla',
    );
  }

  String _rol(Rol rol, String idioma) => esc(texto(idioma, 'rol_${rol.name}'));

  Future<Response> _boveda(Request r, _SesionAdmin s, String idioma, String id, {String? aviso}) async {
    final b = almacen.boveda(id);
    if (b == null) {
      return _pagina(r, idioma, s, 'bovedas', _mensaje('error', texto(idioma, 'noEncontrado')), estado: 404);
    }
    final miembros = almacen.miembros(id);
    final ruta = '$_base/bovedas/${Uri.encodeComponent(id)}';
    final filas = miembros
        .map(
          (m) =>
              '<tr><td><a href="$_base/usuarios/${Uri.encodeComponent(m.usuario)}">${esc(m.nombre)}</a></td>'
              '<td>${_rol(m.rol, idioma)}</td></tr>',
        )
        .join('\n');
    final contenido =
        '''
<p class="volver"><a href="$_base/bovedas">← ${esc(texto(idioma, 'volver'))}</a></p>
<h1>${esc(texto(idioma, 'boveda'))} ${_idCorto(id)}</h1>
${aviso ?? ''}
<p class="suave">${esc(texto(idioma, 'creada'))}: ${_fecha(b.creada, idioma)} · <code>${esc(id)}</code></p>
<h2>${esc(texto(idioma, 'miembros'))}</h2>
<div class="tarjeta tabla"><table>
<tr><th scope="col">${esc(texto(idioma, 'usuario'))}</th><th scope="col">${esc(texto(idioma, 'permiso'))}</th></tr>
$filas
</table></div>
<p class="suave">${esc(texto(idioma, 'avisoMiembros'))}</p>
<h2 class="peligro-titulo">${esc(texto(idioma, 'zonaPeligro'))}</h2>
<div class="tarjeta">
<form method="post" action="$ruta/borrar">${_csrfCampo(s)}
<label class="casilla"><input type="checkbox" name="confirmar" value="si" required> <span>${esc(texto(idioma, 'confirmarBorrado'))}</span></label>
<button class="peligro" type="submit">${esc(texto(idioma, 'borrarBoveda'))}</button>
</form>
</div>''';
    return _pagina(r, idioma, s, 'bovedas', contenido);
  }

  Future<Response> _borrarBoveda(Request r, _SesionAdmin s, String idioma, String id) async {
    // El navegador ya exige la casilla; se comprueba también aquí
    if (_form(r)['confirmar'] != 'si') return _boveda(r, s, idioma, id);
    if (!almacen.borrarBoveda(id)) {
      return _pagina(r, idioma, s, 'bovedas', _mensaje('error', texto(idioma, 'noEncontrado')), estado: 404);
    }
    return _redirigir('$_base/bovedas?ok=bovedaBorrada');
  }

  // --- Usuarios ---

  String _estadoUsuario(bool desactivado, String idioma) =>
      _chip(!desactivado, texto(idioma, desactivado ? 'desactivadoUsuario' : 'activo'));

  Future<Response> _usuarios(Request r, _SesionAdmin s, String idioma) async {
    final lista = almacen.usuarios();
    final filas = lista
        .map(
          (u) =>
              '<tr><td><a href="$_base/usuarios/${Uri.encodeComponent(u.id)}">${esc(u.nombre)}</a></td><td>${_fecha(u.creado, idioma)}</td><td>${u.bovedas}</td>'
              '<td>${u.dispositivos}</td><td>${_estadoUsuario(u.desactivado, idioma)}</td>'
              '<td class="accion"><a href="$_base/usuarios/${Uri.encodeComponent(u.id)}">${esc(texto(idioma, 'ver'))}</a></td></tr>',
        )
        .join('\n');
    final tabla = lista.isEmpty
        ? _vacio(
            '☺',
            texto(idioma, 'sinUsuarios'),
            accion: '<a class="boton" href="$_base/invitaciones">${esc(texto(idioma, 'crearInvitacion'))}</a>',
          )
        : '<div class="tarjeta tabla"><table>'
              '<tr><th scope="col">${esc(texto(idioma, 'usuario'))}</th><th scope="col">${esc(texto(idioma, 'creada'))}</th>'
              '<th scope="col">${esc(texto(idioma, 'bovedas'))}</th><th scope="col">${esc(texto(idioma, 'dispositivosActivos'))}</th>'
              '<th scope="col">${esc(texto(idioma, 'estado'))}</th><th></th></tr>'
              '$filas</table></div>';
    final contenido =
        '<h1>${esc(texto(idioma, 'usuarios'))}</h1>${_confirmacion(r, idioma)}$tabla'
        '<p class="suave">${esc(texto(idioma, 'avisoAltaUsuarios'))} '
        '<a href="$_base/invitaciones">${esc(texto(idioma, 'invitaciones'))}</a></p>';
    return _pagina(r, idioma, s, 'usuarios', contenido);
  }

  Future<Response> _usuario(Request r, _SesionAdmin s, String idioma, String id, {String? aviso}) async {
    final u = almacen.usuario(id);
    if (u == null) {
      return _pagina(r, idioma, s, 'usuarios', _mensaje('error', texto(idioma, 'noEncontrado')), estado: 404);
    }
    final ruta = '$_base/usuarios/${Uri.encodeComponent(id)}';
    final dispositivos = almacen.dispositivos(id);
    final filasDisp = dispositivos
        .map((d) {
          final estado = _chip(!d.revocado, texto(idioma, d.revocado ? 'revocado' : 'activo'));
          final accion = d.revocado
              ? ''
              : '<form class="linea" method="post" action="$ruta/revocar">${_csrfCampo(s)}'
                    '<input type="hidden" name="dispositivo" value="${esc(d.id)}">'
                    '<button class="secundario" type="submit">${esc(texto(idioma, 'revocar'))}</button></form>';
          return '<tr><td>${esc(d.nombre)}<div class="detalle">${_idCorto(d.id)}</div></td>'
              '<td>${_fecha(d.ultimoAcceso, idioma)}</td><td>$estado</td><td class="accion">$accion</td></tr>';
        })
        .join('\n');
    final bovedas = almacen.bovedasDe(id);
    final filasBov = bovedas
        .map(
          (x) =>
              '<tr><td><a href="$_base/bovedas/${Uri.encodeComponent(x.boveda.id)}">${_idCorto(x.boveda.id)}</a></td>'
              '<td>${_rol(x.miembro.rol, idioma)}</td></tr>',
        )
        .join('\n');
    final soloSuyas = almacen.bovedasSoloSuyas(id).length;
    final contenido =
        '''
<p class="volver"><a href="$_base/usuarios">← ${esc(texto(idioma, 'volver'))}</a></p>
<h1>${esc(u.nombre)} ${_estadoUsuario(u.desactivado, idioma)}</h1>
${aviso ?? _confirmacion(r, idioma)}
<p class="suave">${esc(texto(idioma, 'creada'))}: ${_fecha(u.creado, idioma)}</p>
<form method="post" action="$ruta/estado">${_csrfCampo(s)}
<input type="hidden" name="desactivar" value="${u.desactivado ? 'no' : 'si'}">
<button class="secundario" type="submit">${esc(texto(idioma, u.desactivado ? 'activarUsuario' : 'desactivarUsuario'))}</button>
</form>
<p class="suave">${esc(texto(idioma, 'avisoDesactivar'))}</p>
<h2>${esc(texto(idioma, 'dispositivos'))}</h2>
${dispositivos.isEmpty ? _vacio('▢', texto(idioma, 'sinDispositivos')) : '''
<div class="tarjeta tabla"><table>
<tr><th scope="col">${esc(texto(idioma, 'nombre'))}</th><th scope="col">${esc(texto(idioma, 'ultimoAcceso'))}</th><th scope="col">${esc(texto(idioma, 'estado'))}</th><th></th></tr>
$filasDisp
</table></div>'''}
<h2>${esc(texto(idioma, 'bovedas'))}</h2>
${bovedas.isEmpty ? _vacio('▣', texto(idioma, 'sinBovedasUsuario')) : '''
<div class="tarjeta tabla"><table>
<tr><th scope="col">${esc(texto(idioma, 'boveda'))}</th><th scope="col">${esc(texto(idioma, 'permiso'))}</th></tr>
$filasBov
</table></div>'''}
<h2 class="peligro-titulo">${esc(texto(idioma, 'zonaPeligro'))}</h2>
<div class="tarjeta">
<form method="post" action="$ruta/borrar">${_csrfCampo(s)}
<label class="casilla"><input type="checkbox" name="confirmar" value="si" required> <span>${esc(_textoBorradoUsuario(soloSuyas, idioma))}</span></label>
<button class="peligro" type="submit">${esc(texto(idioma, 'borrarUsuario'))}</button>
</form>
</div>''';
    return _pagina(r, idioma, s, 'usuarios', contenido);
  }

  // Sin bóvedas propias no se mencionan; con una, en singular
  static String _textoBorradoUsuario(int soloSuyas, String idioma) => switch (soloSuyas) {
    0 => texto(idioma, 'confirmarBorradoUsuario'),
    1 => texto(idioma, 'confirmarBorradoUsuarioUna'),
    _ => texto(idioma, 'confirmarBorradoUsuarioVarias').replaceAll('{n}', '$soloSuyas'),
  };

  Future<Response> _cambiarEstadoUsuario(Request r, _SesionAdmin s, String idioma, String id) async {
    final desactivar = _form(r)['desactivar'] == 'si';
    if (!almacen.desactivarUsuario(id, desactivar)) {
      return _pagina(r, idioma, s, 'usuarios', _mensaje('error', texto(idioma, 'noEncontrado')), estado: 404);
    }
    final ok = desactivar ? 'usuarioDesactivado' : 'usuarioActivado';
    return _redirigir('$_base/usuarios/${Uri.encodeComponent(id)}?ok=$ok');
  }

  Future<Response> _borrarUsuario(Request r, _SesionAdmin s, String idioma, String id) async {
    if (_form(r)['confirmar'] != 'si') return _usuario(r, s, idioma, id);
    if (!almacen.borrarUsuario(id)) {
      return _pagina(r, idioma, s, 'usuarios', _mensaje('error', texto(idioma, 'noEncontrado')), estado: 404);
    }
    return _redirigir('$_base/usuarios?ok=usuarioBorrado');
  }

  Future<Response> _revocarDispositivo(Request r, _SesionAdmin s, String idioma, String id) async {
    final ok = almacen.revocarDispositivo(id, _form(r)['dispositivo'] ?? '');
    if (!ok) return _usuario(r, s, idioma, id, aviso: _mensaje('error', texto(idioma, 'noEncontrado')));
    return _redirigir('$_base/usuarios/${Uri.encodeComponent(id)}?ok=dispositivoDesconectado');
  }
}
