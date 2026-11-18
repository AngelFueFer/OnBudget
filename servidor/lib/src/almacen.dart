import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'seguridad.dart';

// Permisos de un usuario sobre una bóveda. Los valores se guardan tal cual en la base de datos.
enum Rol {
  lectura, // Solo consulta
  escritura, // Consulta y apunta/edita
  propietario; // Además gestiona miembros y puede borrar la bóveda

  bool get puedeEscribir => this != Rol.lectura;
  bool get esPropietario => this == Rol.propietario;

  static Rol? leer(Object? valor) {
    for (final r in Rol.values) {
      if (r.name == valor) return r;
    }
    return null;
  }
}

class Usuario {
  final String id;
  final String nombre; // En minúsculas; es con lo que se inicia sesión
  final Map<String, Object?> kdf; // Parámetros de Argon2id (opacos para el servidor)
  final Uint8List salAcceso;
  final String hashAcceso;
  final Uint8List clavePublica; // Para que otros le compartan la clave de una bóveda
  final Uint8List clavePrivadaCifrada; // Cifrada con su contraseña maestra; el servidor no puede abrirla
  final DateTime creado;
  final bool desactivado;

  Usuario(
    this.id,
    this.nombre,
    this.kdf,
    this.salAcceso,
    this.hashAcceso,
    this.clavePublica,
    this.clavePrivadaCifrada,
    this.creado,
    this.desactivado,
  );
}

class Boveda {
  final String id;
  final Uint8List nombreCifrado; // El nombre también va cifrado: el servidor no sabe cómo se llama
  final DateTime creada;

  Boveda(this.id, this.nombreCifrado, this.creada);
}

class Miembro {
  final String boveda;
  final String usuario; // id
  final String nombre;
  final Rol rol;
  final Uint8List claveBovedaCifrada; // Clave de la bóveda cifrada para la clave pública de este usuario

  Miembro(this.boveda, this.usuario, this.nombre, this.rol, this.claveBovedaCifrada);

  Map<String, Object?> toJson() => {'usuario': nombre, 'rol': rol.name};
}

class Dispositivo {
  final String id;
  final String usuario;
  final String nombre;
  final DateTime creado;
  final DateTime? ultimoAcceso;
  final bool revocado;

  Dispositivo(this.id, this.usuario, this.nombre, this.creado, this.ultimoAcceso, this.revocado);

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'creado': creado.toIso8601String(),
    'ultimoAcceso': ultimoAcceso?.toIso8601String(),
    'revocado': revocado,
  };
}

class Cambio {
  final int secuencia;
  final String dispositivo;
  final Uint8List datos; // Paquete cifrado tal cual lo envió la app
  final DateTime recibido;

  Cambio(this.secuencia, this.dispositivo, this.datos, this.recibido);

  Map<String, Object?> toJson() => {
    'secuencia': secuencia,
    'dispositivo': dispositivo,
    'datos': base64.encode(datos),
    'recibido': recibido.toIso8601String(),
  };
}

class Instantanea {
  final int hasta;
  final String dispositivo;
  final Uint8List datos;
  final DateTime fecha;

  Instantanea(this.hasta, this.dispositivo, this.datos, this.fecha);
}

// Toda la persistencia del servidor, en un único archivo SQLite dentro de la carpeta de datos.
// El servidor no entiende el contenido: guarda bloques cifrados y metadatos mínimos.
class Almacen {
  static const int _versionEsquema = 2;

  final Database _db;
  // Sustituible en tests
  final DateTime Function() ahora;

  Almacen._(this._db, this.ahora);

  factory Almacen.abrir(String ruta, {DateTime Function()? ahora}) =>
      Almacen._(sqlite3.open(ruta), ahora ?? () => DateTime.now().toUtc()).._preparar();

  factory Almacen.enMemoria({DateTime Function()? ahora}) =>
      Almacen._(sqlite3.openInMemory(), ahora ?? () => DateTime.now().toUtc()).._preparar();

  void cerrar() => _db.dispose();

  void _preparar() {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA foreign_keys = ON');
    final version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version == 1) {
      // v1 (0.1.x) tenía bóvedas con una contraseña compartida y sin usuarios. No se pueden convertir
      // (no hay claves por usuario), así que sus tablas se conservan con el sufijo _v1 en vez de borrarse.
      for (final tabla in ['dispositivos', 'cambios', 'instantaneas', 'bovedas']) {
        _db.execute('ALTER TABLE $tabla RENAME TO ${tabla}_v1');
      }
      _db.execute('DROP INDEX IF EXISTS idx_cambios_boveda');
    }
    if (version < 2) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS invitaciones(
          hash TEXT PRIMARY KEY,
          creada TEXT NOT NULL,
          usada TEXT
        );
        CREATE TABLE usuarios(
          id TEXT PRIMARY KEY,
          nombre TEXT NOT NULL UNIQUE,
          kdf TEXT NOT NULL,
          sal_acceso BLOB NOT NULL,
          hash_acceso TEXT NOT NULL,
          clave_publica BLOB NOT NULL,
          clave_privada_cifrada BLOB NOT NULL,
          creado TEXT NOT NULL,
          desactivado INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE bovedas(
          id TEXT PRIMARY KEY,
          nombre_cifrado BLOB NOT NULL,
          creada TEXT NOT NULL
        );
        CREATE TABLE miembros(
          boveda TEXT NOT NULL REFERENCES bovedas(id) ON DELETE CASCADE,
          usuario TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
          rol TEXT NOT NULL,
          clave_boveda_cifrada BLOB NOT NULL,
          PRIMARY KEY (boveda, usuario)
        );
        CREATE INDEX idx_miembros_usuario ON miembros(usuario);
        CREATE TABLE dispositivos(
          id TEXT NOT NULL,
          usuario TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
          nombre TEXT NOT NULL,
          hash_token TEXT NOT NULL UNIQUE,
          creado TEXT NOT NULL,
          ultimo_acceso TEXT,
          revocado INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (usuario, id)
        );
        CREATE TABLE cambios(
          secuencia INTEGER PRIMARY KEY AUTOINCREMENT,
          boveda TEXT NOT NULL REFERENCES bovedas(id) ON DELETE CASCADE,
          usuario TEXT,
          dispositivo TEXT NOT NULL,
          datos BLOB NOT NULL,
          recibido TEXT NOT NULL
        );
        CREATE INDEX idx_cambios_boveda ON cambios(boveda, secuencia);
        CREATE TABLE instantaneas(
          boveda TEXT PRIMARY KEY REFERENCES bovedas(id) ON DELETE CASCADE,
          hasta INTEGER NOT NULL,
          dispositivo TEXT NOT NULL,
          datos BLOB NOT NULL,
          fecha TEXT NOT NULL
        );
      ''');
    }
    // Las versiones futuras del esquema se añadirán aquí con "if (version < N)"
    _db.execute('PRAGMA user_version = $_versionEsquema');
  }

  String _fecha() => ahora().toIso8601String();

  T _transaccion<T>(T Function() cuerpo) {
    _db.execute('BEGIN');
    try {
      final r = cuerpo();
      _db.execute('COMMIT');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // --- Invitaciones (las crea el administrador; cada una permite registrar un usuario) ---

  String crearInvitacion() {
    final codigo = nuevoCodigoInvitacion();
    _db.execute('INSERT INTO invitaciones(hash, creada) VALUES (?, ?)', [hashDe(codigo), _fecha()]);
    return codigo;
  }

  // Marca la invitación como usada; false si no existe o ya se usó
  bool consumirInvitacion(String codigo) {
    _db.execute('UPDATE invitaciones SET usada = ? WHERE hash = ? AND usada IS NULL', [
      _fecha(),
      hashDe(normalizarInvitacion(codigo)),
    ]);
    return _db.updatedRows == 1;
  }

  int invitacionesPendientes() =>
      _db.select('SELECT COUNT(*) FROM invitaciones WHERE usada IS NULL').first.columnAt(0) as int;

  void anularInvitaciones() => _db.execute('DELETE FROM invitaciones WHERE usada IS NULL');

  // Invitaciones sin usar. El código no se puede mostrar (solo se guarda su hash): se identifican
  // por los primeros caracteres del hash para poder anularlas una a una desde el panel.
  List<({String id, DateTime creada})> invitacionesSinUsar() => _db
      .select('SELECT hash, creada FROM invitaciones WHERE usada IS NULL ORDER BY creada DESC')
      .map((f) => (id: (f['hash'] as String).substring(0, 12), creada: DateTime.parse(f['creada'] as String)))
      .toList();

  bool anularInvitacion(String id) {
    if (!RegExp(r'^[0-9a-f]{12}$').hasMatch(id)) return false;
    _db.execute("DELETE FROM invitaciones WHERE usada IS NULL AND hash LIKE ? || '%'", [id]);
    return _db.updatedRows == 1;
  }

  // --- Usuarios ---

  static String normalizarNombre(String nombre) => nombre.trim().toLowerCase();

  // Letras, números, punto, guion y guion bajo; de 3 a 32 caracteres
  static bool nombreValido(String nombre) => RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(nombre);

  // Registra el usuario consumiendo la invitación en la misma transacción.
  // Devuelve null si la invitación no vale; lanza [SqliteException] si el nombre ya existe.
  Usuario? registrarUsuario({
    required String invitacion,
    required String nombre,
    required Map<String, Object?> kdf,
    required Uint8List salAcceso,
    required String hashAcceso,
    required Uint8List clavePublica,
    required Uint8List clavePrivadaCifrada,
  }) => _transaccion(() {
    if (!consumirInvitacion(invitacion)) return null;
    final u = Usuario(
      nuevoUuid(),
      normalizarNombre(nombre),
      kdf,
      salAcceso,
      hashAcceso,
      clavePublica,
      clavePrivadaCifrada,
      ahora(),
      false,
    );
    _db.execute(
      'INSERT INTO usuarios(id, nombre, kdf, sal_acceso, hash_acceso, clave_publica, clave_privada_cifrada, creado) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        u.id,
        u.nombre,
        jsonEncode(kdf),
        salAcceso,
        hashAcceso,
        clavePublica,
        clavePrivadaCifrada,
        u.creado.toIso8601String(),
      ],
    );
    return u;
  });

  bool existeUsuario(String nombre) =>
      _db.select('SELECT 1 FROM usuarios WHERE nombre = ?', [normalizarNombre(nombre)]).isNotEmpty;

  Usuario? usuarioPorNombre(String nombre) =>
      _unUsuario(_db.select('SELECT * FROM usuarios WHERE nombre = ?', [normalizarNombre(nombre)]));

  Usuario? usuario(String id) => _unUsuario(_db.select('SELECT * FROM usuarios WHERE id = ?', [id]));

  Usuario? _unUsuario(ResultSet filas) {
    if (filas.isEmpty) return null;
    final f = filas.first;
    return Usuario(
      f['id'] as String,
      f['nombre'] as String,
      (jsonDecode(f['kdf'] as String) as Map).cast<String, Object?>(),
      Uint8List.fromList(f['sal_acceso'] as List<int>),
      f['hash_acceso'] as String,
      Uint8List.fromList(f['clave_publica'] as List<int>),
      Uint8List.fromList(f['clave_privada_cifrada'] as List<int>),
      DateTime.parse(f['creado'] as String),
      f['desactivado'] == 1,
    );
  }

  List<({String id, String nombre, DateTime creado, bool desactivado, int bovedas, int dispositivos})> usuarios() => _db
      .select('''
        SELECT u.id, u.nombre, u.creado, u.desactivado,
          (SELECT COUNT(*) FROM miembros m WHERE m.usuario = u.id) AS bovedas,
          (SELECT COUNT(*) FROM dispositivos d WHERE d.usuario = u.id AND d.revocado = 0) AS dispositivos
        FROM usuarios u ORDER BY u.nombre
      ''')
      .map(
        (f) => (
          id: f['id'] as String,
          nombre: f['nombre'] as String,
          creado: DateTime.parse(f['creado'] as String),
          desactivado: f['desactivado'] == 1,
          bovedas: f['bovedas'] as int,
          dispositivos: f['dispositivos'] as int,
        ),
      )
      .toList();

  // Desactivar impide iniciar sesión y cierra todas las sesiones, sin borrar nada
  bool desactivarUsuario(String id, bool desactivado) => _transaccion(() {
    _db.execute('UPDATE usuarios SET desactivado = ? WHERE id = ?', [desactivado ? 1 : 0, id]);
    final ok = _db.updatedRows == 1;
    if (ok && desactivado) _revocarTodos(id);
    return ok;
  });

  // Bóvedas en las que el usuario es el único propietario (se quedarían sin nadie que las gestione)
  List<String> bovedasSoloSuyas(String usuario) => _db
      .select(
        '''
        SELECT m.boveda FROM miembros m
        WHERE m.usuario = ? AND m.rol = ?
          AND NOT EXISTS (SELECT 1 FROM miembros o WHERE o.boveda = m.boveda AND o.usuario != m.usuario AND o.rol = ?)
      ''',
        [usuario, Rol.propietario.name, Rol.propietario.name],
      )
      .map((f) => f['boveda'] as String)
      .toList();

  // Borra el usuario y las bóvedas de las que era el único propietario
  bool borrarUsuario(String id) => _transaccion(() {
    for (final b in bovedasSoloSuyas(id)) {
      _db.execute('DELETE FROM bovedas WHERE id = ?', [b]);
    }
    _db.execute('DELETE FROM usuarios WHERE id = ?', [id]);
    return _db.updatedRows == 1;
  });

  // --- Dispositivos y sesiones ---

  // Registra (o vuelve a registrar) un dispositivo y devuelve su token nuevo
  String abrirSesion(String usuario, String dispositivo, String nombre) {
    final token = nuevoToken();
    _db.execute(
      '''
      INSERT INTO dispositivos(id, usuario, nombre, hash_token, creado, ultimo_acceso, revocado)
      VALUES (?, ?, ?, ?, ?, ?, 0)
      ON CONFLICT(usuario, id) DO UPDATE SET
        nombre = excluded.nombre, hash_token = excluded.hash_token,
        ultimo_acceso = excluded.ultimo_acceso, revocado = 0
    ''',
      [dispositivo, usuario, nombre, hashDe(token), _fecha(), _fecha()],
    );
    return token;
  }

  // Dispositivo dueño del token, si no está revocado ni su usuario desactivado. Actualiza su último acceso.
  Dispositivo? dispositivoPorToken(String token) {
    final filas = _db.select(
      'SELECT d.* FROM dispositivos d JOIN usuarios u ON u.id = d.usuario '
      'WHERE d.hash_token = ? AND d.revocado = 0 AND u.desactivado = 0',
      [hashDe(token)],
    );
    if (filas.isEmpty) return null;
    final f = filas.first;
    _db.execute('UPDATE dispositivos SET ultimo_acceso = ? WHERE usuario = ? AND id = ?', [
      _fecha(),
      f['usuario'],
      f['id'],
    ]);
    return _dispositivo(f);
  }

  List<Dispositivo> dispositivos(String usuario) =>
      _db.select('SELECT * FROM dispositivos WHERE usuario = ? ORDER BY creado', [usuario]).map(_dispositivo).toList();

  bool revocarDispositivo(String usuario, String id) {
    // El token se sustituye para que no pueda volver a usarse aunque se reactive
    _db.execute('UPDATE dispositivos SET revocado = 1, hash_token = ? WHERE usuario = ? AND id = ? AND revocado = 0', [
      hashDe(nuevoToken()),
      usuario,
      id,
    ]);
    return _db.updatedRows == 1;
  }

  void _revocarTodos(String usuario) {
    for (final d in dispositivos(usuario)) {
      revocarDispositivo(usuario, d.id);
    }
  }

  Dispositivo _dispositivo(Row f) => Dispositivo(
    f['id'] as String,
    f['usuario'] as String,
    f['nombre'] as String,
    DateTime.parse(f['creado'] as String),
    f['ultimo_acceso'] == null ? null : DateTime.parse(f['ultimo_acceso'] as String),
    f['revocado'] == 1,
  );

  // --- Bóvedas y miembros ---

  // Crea la bóveda con su creador como propietario
  Boveda crearBoveda(String usuario, Uint8List nombreCifrado, Uint8List claveBovedaCifrada) => _transaccion(() {
    final b = Boveda(nuevoUuid(), nombreCifrado, ahora());
    _db.execute('INSERT INTO bovedas(id, nombre_cifrado, creada) VALUES (?, ?, ?)', [
      b.id,
      nombreCifrado,
      b.creada.toIso8601String(),
    ]);
    _db.execute('INSERT INTO miembros(boveda, usuario, rol, clave_boveda_cifrada) VALUES (?, ?, ?, ?)', [
      b.id,
      usuario,
      Rol.propietario.name,
      claveBovedaCifrada,
    ]);
    return b;
  });

  Boveda? boveda(String id) {
    final filas = _db.select('SELECT * FROM bovedas WHERE id = ?', [id]);
    if (filas.isEmpty) return null;
    final f = filas.first;
    return Boveda(
      f['id'] as String,
      Uint8List.fromList(f['nombre_cifrado'] as List<int>),
      DateTime.parse(f['creada'] as String),
    );
  }

  List<({String id, DateTime creada, int miembros, int cambios})> bovedas() => _db
      .select('''
        SELECT b.id, b.creada,
          (SELECT COUNT(*) FROM miembros m WHERE m.boveda = b.id) AS miembros,
          (SELECT COUNT(*) FROM cambios c WHERE c.boveda = b.id) AS cambios
        FROM bovedas b ORDER BY b.creada
      ''')
      .map(
        (f) => (
          id: f['id'] as String,
          creada: DateTime.parse(f['creada'] as String),
          miembros: f['miembros'] as int,
          cambios: f['cambios'] as int,
        ),
      )
      .toList();

  // Borra la bóveda con todo su contenido (miembros, cambios, instantánea)
  bool borrarBoveda(String id) {
    _db.execute('DELETE FROM bovedas WHERE id = ?', [id]);
    return _db.updatedRows == 1;
  }

  static const String _consultaMiembros = 'SELECT m.*, u.nombre FROM miembros m JOIN usuarios u ON u.id = m.usuario';

  Miembro _miembro(Row f) => Miembro(
    f['boveda'] as String,
    f['usuario'] as String,
    f['nombre'] as String,
    Rol.leer(f['rol']) ?? Rol.lectura,
    Uint8List.fromList(f['clave_boveda_cifrada'] as List<int>),
  );

  Miembro? miembro(String boveda, String usuario) {
    final filas = _db.select('$_consultaMiembros WHERE m.boveda = ? AND m.usuario = ?', [boveda, usuario]);
    return filas.isEmpty ? null : _miembro(filas.first);
  }

  List<Miembro> miembros(String boveda) =>
      _db.select('$_consultaMiembros WHERE m.boveda = ? ORDER BY u.nombre', [boveda]).map(_miembro).toList();

  // Bóvedas a las que pertenece un usuario, con su rol y su copia de la clave
  List<({Boveda boveda, Miembro miembro})> bovedasDe(String usuario) => _db
      .select(
        'SELECT m.*, u.nombre, b.nombre_cifrado, b.creada FROM miembros m '
        'JOIN usuarios u ON u.id = m.usuario JOIN bovedas b ON b.id = m.boveda '
        'WHERE m.usuario = ? ORDER BY b.creada',
        [usuario],
      )
      .map(
        (f) => (
          boveda: Boveda(
            f['boveda'] as String,
            Uint8List.fromList(f['nombre_cifrado'] as List<int>),
            DateTime.parse(f['creada'] as String),
          ),
          miembro: _miembro(f),
        ),
      )
      .toList();

  int _propietarios(String boveda) =>
      _db
              .select('SELECT COUNT(*) FROM miembros WHERE boveda = ? AND rol = ?', [boveda, Rol.propietario.name])
              .first
              .columnAt(0)
          as int;

  // Añade un miembro o le cambia el rol. [claveBovedaCifrada] es obligatoria al añadirlo.
  // Devuelve false si con el cambio la bóveda se quedaría sin propietario.
  bool guardarMiembro(String boveda, String usuario, Rol rol, Uint8List? claveBovedaCifrada) => _transaccion(() {
    final actual = miembro(boveda, usuario);
    if (actual == null) {
      if (claveBovedaCifrada == null) return false;
      _db.execute('INSERT INTO miembros(boveda, usuario, rol, clave_boveda_cifrada) VALUES (?, ?, ?, ?)', [
        boveda,
        usuario,
        rol.name,
        claveBovedaCifrada,
      ]);
      return true;
    }
    if (actual.rol.esPropietario && !rol.esPropietario && _propietarios(boveda) == 1) return false;
    _db.execute('UPDATE miembros SET rol = ?, clave_boveda_cifrada = ? WHERE boveda = ? AND usuario = ?', [
      rol.name,
      claveBovedaCifrada ?? actual.claveBovedaCifrada,
      boveda,
      usuario,
    ]);
    return true;
  });

  // false si no es miembro o es el único propietario
  bool quitarMiembro(String boveda, String usuario) => _transaccion(() {
    final actual = miembro(boveda, usuario);
    if (actual == null) return false;
    if (actual.rol.esPropietario && _propietarios(boveda) == 1) return false;
    _db.execute('DELETE FROM miembros WHERE boveda = ? AND usuario = ?', [boveda, usuario]);
    return true;
  });

  // --- Cambios ---

  // Guarda los paquetes en orden, en una transacción, y devuelve sus números de secuencia
  List<int> guardarCambios(String boveda, String usuario, String dispositivo, List<Uint8List> paquetes) =>
      _transaccion(() {
        final secuencias = <int>[];
        final fecha = _fecha();
        final sentencia = _db.prepare(
          'INSERT INTO cambios(boveda, usuario, dispositivo, datos, recibido) VALUES (?, ?, ?, ?, ?)',
        );
        try {
          for (final datos in paquetes) {
            sentencia.execute([boveda, usuario, dispositivo, datos, fecha]);
            secuencias.add(_db.lastInsertRowId);
          }
        } finally {
          sentencia.dispose();
        }
        return secuencias;
      });

  List<Cambio> cambiosDesde(String boveda, int desde, int limite) => _db
      .select('SELECT * FROM cambios WHERE boveda = ? AND secuencia > ? ORDER BY secuencia LIMIT ?', [
        boveda,
        desde,
        limite,
      ])
      .map(
        (f) => Cambio(
          f['secuencia'] as int,
          f['dispositivo'] as String,
          Uint8List.fromList(f['datos'] as List<int>),
          DateTime.parse(f['recibido'] as String),
        ),
      )
      .toList();

  int ultimaSecuencia(String boveda) =>
      (_db.select('SELECT MAX(secuencia) FROM cambios WHERE boveda = ?', [boveda]).first.columnAt(0) as int?) ??
      (instantanea(boveda)?.hasta ?? 0);

  // --- Instantáneas ---

  Instantanea? instantanea(String boveda) {
    final filas = _db.select('SELECT * FROM instantaneas WHERE boveda = ?', [boveda]);
    if (filas.isEmpty) return null;
    final f = filas.first;
    return Instantanea(
      f['hasta'] as int,
      f['dispositivo'] as String,
      Uint8List.fromList(f['datos'] as List<int>),
      DateTime.parse(f['fecha'] as String),
    );
  }

  // Sustituye la instantánea y descarta los cambios que ya contiene, para que el historial no crezca sin límite
  void guardarInstantanea(String boveda, String dispositivo, int hasta, Uint8List datos) => _transaccion(() {
    _db.execute(
      '''
      INSERT INTO instantaneas(boveda, hasta, dispositivo, datos, fecha) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(boveda) DO UPDATE SET hasta = excluded.hasta, dispositivo = excluded.dispositivo,
        datos = excluded.datos, fecha = excluded.fecha
    ''',
      [boveda, hasta, dispositivo, datos, _fecha()],
    );
    _db.execute('DELETE FROM cambios WHERE boveda = ? AND secuencia <= ?', [boveda, hasta]);
  });

  // --- Cifras para el panel de administración ---

  ({int usuarios, int bovedas, int dispositivosActivos, int cambios, int invitaciones}) resumen() {
    final f = _db.select('''
      SELECT
        (SELECT COUNT(*) FROM usuarios) AS usuarios,
        (SELECT COUNT(*) FROM bovedas) AS bovedas,
        (SELECT COUNT(*) FROM dispositivos WHERE revocado = 0) AS dispositivos,
        (SELECT COUNT(*) FROM cambios) AS cambios,
        (SELECT COUNT(*) FROM invitaciones WHERE usada IS NULL) AS invitaciones
    ''').first;
    return (
      usuarios: f['usuarios'] as int,
      bovedas: f['bovedas'] as int,
      dispositivosActivos: f['dispositivos'] as int,
      cambios: f['cambios'] as int,
      invitaciones: f['invitaciones'] as int,
    );
  }

  int tamanoBytes() {
    final f = _db.select('SELECT page_count * page_size AS bytes FROM pragma_page_count(), pragma_page_size()').first;
    return f['bytes'] as int;
  }
}
