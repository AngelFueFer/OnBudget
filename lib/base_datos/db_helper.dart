import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/modelos/activo.dart';
import 'package:presupuesto_familiar/sincronizacion/fusion.dart';
import 'package:presupuesto_familiar/sincronizacion/identificadores.dart';
import 'package:presupuesto_familiar/sincronizacion/reloj_hibrido.dart';

class DBHelper {
  static const int versionBaseDatos = 6;
  // Tablas cuyas filas se sincronizan entre dispositivos
  static const List<String> tablasSincronizables = [DBKeys.tableTransacciones, DBKeys.tableActivos];

  static final DBHelper _instancia = DBHelper._interno();
  factory DBHelper() => _instancia;
  DBHelper._interno();

  // Sustituibles en tests (base de datos en memoria con sqflite_common_ffi y hora controlada)
  static DatabaseFactory? fabricaBaseDatos;
  static String? rutaBaseDatos;
  static DateTime Function() ahora = DateTime.now;

  Database? _baseDatos;
  RelojHibrido? _reloj;

  Future<Database> get baseDatos async {
    if (_baseDatos != null) return _baseDatos!;
    _baseDatos = await _iniciarBaseDatos();
    return _baseDatos!;
  }

  // Cierra la base y olvida el reloj (tests y, más adelante, cambio de bóveda)
  Future<void> cerrar() async {
    await _baseDatos?.close();
    _baseDatos = null;
    _reloj = null;
  }

  Future<Database> _iniciarBaseDatos() async {
    final fabrica = fabricaBaseDatos ?? databaseFactory;
    final ruta = rutaBaseDatos ?? join(await getDatabasesPath(), DBKeys.nombreBaseDatos);

    return await fabrica.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: versionBaseDatos,
        onCreate: _crearBaseDatos,
        onUpgrade: _actualizarBaseDatos,
      ),
    );
  }

  // Migraciones para instalaciones existentes (no se pierden datos)
  Future<void> _actualizarBaseDatos(Database db, int versionAnterior, int versionNueva) async {
    if (versionAnterior < 2) {
      // v2: método de pago de cada transacción
      await db.execute('ALTER TABLE ${DBKeys.tableTransacciones} ADD COLUMN ${DBKeys.columnMetodoPago} TEXT');
      await db.execute('ALTER TABLE ${DBKeys.tableTransacciones} ADD COLUMN ${DBKeys.columnTarjeta} TEXT');
    }
    if (versionAnterior < 3) {
      // v3: cuenta de ahorro (banco) de cada movimiento de Ahorro
      await db.execute('ALTER TABLE ${DBKeys.tableTransacciones} ADD COLUMN ${DBKeys.columnCuentaAhorro} TEXT');
    }
    if (versionAnterior < 4) {
      // v4: tipo de inversión, nombre personalizado e ISIN de cada activo
      await db.execute('ALTER TABLE ${DBKeys.tableActivos} ADD COLUMN ${DBKeys.columnTipo} TEXT');
      await db.execute('ALTER TABLE ${DBKeys.tableActivos} ADD COLUMN ${DBKeys.columnNombre} TEXT');
      await db.execute('ALTER TABLE ${DBKeys.tableActivos} ADD COLUMN ${DBKeys.columnIsin} TEXT');
    }
    if (versionAnterior < 5) {
      // v5: foto del tiquet de cada gasto
      await db.execute('ALTER TABLE ${DBKeys.tableTransacciones} ADD COLUMN ${DBKeys.columnTiquet} TEXT');
    }
    if (versionAnterior < 6) {
      // v6: preparación para sincronizar. Solo añade columnas y una tabla; las filas existentes
      // reciben un uuid y relojes iniciales para que puedan subirse al servidor más adelante.
      for (final tabla in tablasSincronizables) {
        await db.execute('ALTER TABLE $tabla ADD COLUMN ${DBKeys.columnUuid} TEXT');
        await db.execute('ALTER TABLE $tabla ADD COLUMN ${DBKeys.columnRelojes} TEXT');
        await db.execute('ALTER TABLE $tabla ADD COLUMN ${DBKeys.columnModificado} TEXT');
        await db.execute('ALTER TABLE $tabla ADD COLUMN ${DBKeys.columnBorrado} INTEGER NOT NULL DEFAULT 0');
        await db.execute('ALTER TABLE $tabla ADD COLUMN ${DBKeys.columnDispositivo} TEXT');
      }
      final reloj = await _obtenerReloj();
      for (final tabla in tablasSincronizables) {
        final filas = await db.query(tabla);
        for (final fila in filas) {
          final marca = reloj.siguiente();
          await db.update(
            tabla,
            {
              DBKeys.columnUuid: nuevoUuid(),
              DBKeys.columnRelojes: jsonEncode(marcarCambios(null, fila, const {}, marca)),
              DBKeys.columnModificado: marca,
              DBKeys.columnDispositivo: reloj.dispositivo,
            },
            where: '${DBKeys.columnId} = ?',
            whereArgs: [fila[DBKeys.columnId]],
          );
        }
        await _crearIndiceUuid(db, tabla);
      }
      await _crearTablaCambios(db);
    }
  }

  Future<void> _crearBaseDatos(Database db, int version) async {
    // Columnas de sincronización comunes (ver v6)
    final columnasSync = '''
        ${DBKeys.columnUuid} TEXT,
        ${DBKeys.columnRelojes} TEXT,
        ${DBKeys.columnModificado} TEXT,
        ${DBKeys.columnBorrado} INTEGER NOT NULL DEFAULT 0,
        ${DBKeys.columnDispositivo} TEXT''';

    // Tabla 1: Dinero plano
    await db.execute('''
      CREATE TABLE ${DBKeys.tableTransacciones}(
        ${DBKeys.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBKeys.columnMonto} INTEGER,
        ${DBKeys.columnConcepto} TEXT,
        ${DBKeys.columnFecha} TEXT,
        ${DBKeys.columnCategoria} TEXT,
        ${DBKeys.columnEsIngreso} INTEGER,
        ${DBKeys.columnTarro} TEXT,
        ${DBKeys.columnMetodoPago} TEXT,
        ${DBKeys.columnTarjeta} TEXT,
        ${DBKeys.columnCuentaAhorro} TEXT,
        ${DBKeys.columnTiquet} TEXT,
$columnasSync
      )
    ''');

    // Tabla 2: Mercado de valores
    await db.execute('''
      CREATE TABLE ${DBKeys.tableActivos}(
        ${DBKeys.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBKeys.columnTicker} TEXT,
        ${DBKeys.columnCantidad} REAL,
        ${DBKeys.columnPrecioCompra} REAL,
        ${DBKeys.columnTipo} TEXT,
        ${DBKeys.columnNombre} TEXT,
        ${DBKeys.columnIsin} TEXT,
$columnasSync
      )
    ''');

    for (final tabla in tablasSincronizables) {
      await _crearIndiceUuid(db, tabla);
    }
    await _crearTablaCambios(db);
  }

  Future<void> _crearIndiceUuid(Database db, String tabla) async {
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_${tabla}_${DBKeys.columnUuid} ON $tabla(${DBKeys.columnUuid})');
  }

  // Cola de filas modificadas localmente pendientes de subir. Basta con (tabla, uuid): al subir
  // se lee la fila actual con sus relojes, así varios cambios seguidos viajan como uno.
  Future<void> _crearTablaCambios(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DBKeys.tableCambiosPendientes}(
        ${DBKeys.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DBKeys.columnEntidad} TEXT NOT NULL,
        ${DBKeys.columnUuid} TEXT NOT NULL,
        ${DBKeys.columnReloj} TEXT NOT NULL
      )
    ''');
  }

  // --- RELOJ E IDENTIDAD DEL DISPOSITIVO ---

  Future<RelojHibrido> _obtenerReloj() async {
    if (_reloj != null) return _reloj!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(DBKeys.idDispositivo);
    if (id == null) {
      id = nuevoUuid();
      await prefs.setString(DBKeys.idDispositivo, id);
    }
    _reloj = RelojHibrido(id, ahora: () => ahora());
    return _reloj!;
  }

  // --- ESCRITURA COMÚN A LAS TABLAS SINCRONIZABLES ---
  // Toda escritura pasa por aquí para sellar relojes y apuntar el cambio en la cola,
  // en la misma transacción, de modo que nunca se pierde un cambio aunque la app se cierre.

  Future<int> _insertar(String tabla, Map<String, Object?> datos) async {
    final db = await baseDatos;
    final reloj = await _obtenerReloj();
    return db.transaction((txn) async {
      final id = datos[DBKeys.columnId];
      if (id != null) {
        // Reinsertar con id existente (antes era un "replace"): se trata como edición
        final existente = await txn.query(tabla, where: '${DBKeys.columnId} = ?', whereArgs: [id]);
        if (existente.isNotEmpty) {
          await _actualizarEn(txn, tabla, existente.first, datos, reloj);
          return id as int;
        }
      }
      final marca = reloj.siguiente();
      final uuid = nuevoUuid();
      final fila = {...datos, DBKeys.columnBorrado: 0};
      final idNuevo = await txn.insert(tabla, {
        ...fila,
        DBKeys.columnUuid: uuid,
        DBKeys.columnRelojes: jsonEncode(marcarCambios(null, fila, const {}, marca)),
        DBKeys.columnModificado: marca,
        DBKeys.columnDispositivo: reloj.dispositivo,
      });
      await _apuntarCambio(txn, tabla, uuid, marca);
      return idNuevo;
    });
  }

  Future<int> _actualizar(String tabla, Map<String, Object?> datos) async {
    final db = await baseDatos;
    final reloj = await _obtenerReloj();
    return db.transaction((txn) async {
      final existente = await txn.query(tabla, where: '${DBKeys.columnId} = ?', whereArgs: [datos[DBKeys.columnId]]);
      if (existente.isEmpty) return 0;
      return _actualizarEn(txn, tabla, existente.first, datos, reloj);
    });
  }

  Future<int> _actualizarEn(
    Transaction txn,
    String tabla,
    Map<String, Object?> anterior,
    Map<String, Object?> datos,
    RelojHibrido reloj,
  ) async {
    final marca = reloj.siguiente();
    // Editar una fila deja claro que está viva: si otro móvil la borró antes, la edición la recupera
    final nueva = {...datos, DBKeys.columnBorrado: 0};
    final relojes = marcarCambios(anterior, nueva, leerRelojes(anterior[DBKeys.columnRelojes]), marca);
    relojes[DBKeys.columnBorrado] = marca;
    final uuid = anterior[DBKeys.columnUuid] as String;
    final filas = await txn.update(
      tabla,
      {
        ...nueva,
        DBKeys.columnRelojes: jsonEncode(relojes),
        DBKeys.columnModificado: marca,
        DBKeys.columnDispositivo: reloj.dispositivo,
      },
      where: '${DBKeys.columnId} = ?',
      whereArgs: [anterior[DBKeys.columnId]],
    );
    await _apuntarCambio(txn, tabla, uuid, marca);
    return filas;
  }

  // Borrado lógico: la fila se queda marcada para que el borrado llegue al resto de dispositivos
  Future<int> _eliminar(String tabla, int id) async {
    final db = await baseDatos;
    final reloj = await _obtenerReloj();
    return db.transaction((txn) async {
      final existente = await txn.query(tabla, where: '${DBKeys.columnId} = ?', whereArgs: [id]);
      if (existente.isEmpty) return 0;
      final anterior = existente.first;
      final marca = reloj.siguiente();
      final relojes = leerRelojes(anterior[DBKeys.columnRelojes])..[DBKeys.columnBorrado] = marca;
      final filas = await txn.update(
        tabla,
        {
          DBKeys.columnBorrado: 1,
          DBKeys.columnRelojes: jsonEncode(relojes),
          DBKeys.columnModificado: marca,
          DBKeys.columnDispositivo: reloj.dispositivo,
        },
        where: '${DBKeys.columnId} = ?',
        whereArgs: [id],
      );
      await _apuntarCambio(txn, tabla, anterior[DBKeys.columnUuid] as String, marca);
      return filas;
    });
  }

  Future<void> _apuntarCambio(Transaction txn, String tabla, String uuid, String marca) async {
    await txn.insert(DBKeys.tableCambiosPendientes, {
      DBKeys.columnEntidad: tabla,
      DBKeys.columnUuid: uuid,
      DBKeys.columnReloj: marca,
    });
  }

  // --- PREPARACIÓN DE LA SINCRONIZACIÓN (la usará el cliente de la fase 4) ---

  // Filas pendientes de subir, una por (tabla, uuid), en su estado actual con relojes.
  // [hastaId] es el último apunte leído, para vaciar la cola sin perder lo escrito mientras tanto.
  Future<({int hastaId, List<({String tabla, Map<String, Object?> fila})> filas})> obtenerCambiosPendientes() async {
    final db = await baseDatos;
    final pendientes = await db.query(DBKeys.tableCambiosPendientes, orderBy: DBKeys.columnId);
    final vistos = <String>{};
    final filas = <({String tabla, Map<String, Object?> fila})>[];
    var hastaId = 0;
    for (final p in pendientes) {
      hastaId = p[DBKeys.columnId] as int;
      final tabla = p[DBKeys.columnEntidad] as String;
      final uuid = p[DBKeys.columnUuid] as String;
      if (!vistos.add('$tabla/$uuid')) continue;
      final actual = await db.query(tabla, where: '${DBKeys.columnUuid} = ?', whereArgs: [uuid]);
      if (actual.isEmpty) continue;
      filas.add((tabla: tabla, fila: Map<String, Object?>.from(actual.first)..remove(DBKeys.columnId)));
    }
    return (hastaId: hastaId, filas: filas);
  }

  // Vacía la cola hasta el id indicado (tras confirmar el servidor la subida)
  Future<void> descartarCambiosHasta(int idMaximo) async {
    final db = await baseDatos;
    await db.delete(DBKeys.tableCambiosPendientes, where: '${DBKeys.columnId} <= ?', whereArgs: [idMaximo]);
  }

  // Aplica una fila llegada de otro dispositivo fusionándola campo a campo con la local.
  // No se apunta en la cola: ya está en el servidor.
  Future<void> aplicarFilaRemota(String tabla, Map<String, Object?> remota) async {
    if (!tablasSincronizables.contains(tabla)) return;
    final db = await baseDatos;
    final reloj = await _obtenerReloj();
    final modificadoRemoto = remota[DBKeys.columnModificado];
    if (modificadoRemoto is String) reloj.recibir(modificadoRemoto);
    await db.transaction((txn) async {
      final existente = await txn.query(tabla, where: '${DBKeys.columnUuid} = ?', whereArgs: [remota[DBKeys.columnUuid]]);
      final local = existente.isEmpty ? null : existente.first;
      // Solo se aceptan columnas que la tabla conoce (una versión más nueva puede traer más)
      final columnas = (await txn.rawQuery('PRAGMA table_info($tabla)')).map((c) => c['name'] as String).toSet();
      final fusionada = fusionarFila(local: local, remota: remota)..removeWhere((k, _) => !columnas.contains(k));
      if (local == null) {
        await txn.insert(tabla, fusionada);
      } else {
        await txn.update(tabla, fusionada, where: '${DBKeys.columnId} = ?', whereArgs: [local[DBKeys.columnId]]);
      }
    });
  }

  // --- MÉTODOS PARA TRANSACCIONES (Dinero) ---
  // Las lecturas ignoran las filas borradas

  static const String _soloVivas = '${DBKeys.columnBorrado} = 0';

  Future<int> insertarTransaccion(Transaccion transaccion) => _insertar(DBKeys.tableTransacciones, transaccion.toMap());

  Future<List<Transaccion>> obtenerTransacciones() async {
    final db = await baseDatos;
    final mapas = await db.query(DBKeys.tableTransacciones, where: _soloVivas, orderBy: '${DBKeys.columnId} DESC');
    return mapas.map((m) => Transaccion.fromMap(m)).toList();
  }

  // Mueve los movimientos de Ahorro de una cuenta de ahorro a otra (null = sin cuenta asignada).
  // Fila a fila para que cada cambio quede sellado y se sincronice.
  Future<int> reasignarCuentaAhorro(String? desde, String? hacia) async {
    final db = await baseDatos;
    final condicion = desde == null ? '${DBKeys.columnCuentaAhorro} IS NULL' : '${DBKeys.columnCuentaAhorro} = ?';
    final filas = await db.query(
      DBKeys.tableTransacciones,
      where: '${DBKeys.columnTarro} = ? AND $condicion AND $_soloVivas',
      whereArgs: [AppStrings.ahorro, ?desde],
    );
    var total = 0;
    for (final fila in filas) {
      total += await _actualizar(DBKeys.tableTransacciones, {
        DBKeys.columnId: fila[DBKeys.columnId],
        DBKeys.columnCuentaAhorro: hacia,
      });
    }
    return total;
  }

  Future<List<Transaccion>> obtenerTransaccionesPorCuenta(String cuenta) async {
    final db = await baseDatos;
    final mapas = await db.query(
      DBKeys.tableTransacciones,
      where: '${DBKeys.columnTarro} = ? AND $_soloVivas',
      whereArgs: [cuenta],
      orderBy: '${DBKeys.columnId} DESC',
    );
    return mapas.map((m) => Transaccion.fromMap(m)).toList();
  }

  Future<int> insertarActivo(ActivoFinanciero activo) => _insertar(DBKeys.tableActivos, activo.toMap());

  Future<List<ActivoFinanciero>> obtenerActivos() async {
    final db = await baseDatos;
    final mapas = await db.query(DBKeys.tableActivos, where: _soloVivas, orderBy: '${DBKeys.columnId} DESC');
    return mapas.map((m) => ActivoFinanciero.fromMap(m)).toList();
  }

  Future<int> actualizarTransaccion(Transaccion transaccion) => _actualizar(DBKeys.tableTransacciones, transaccion.toMap());

  Future<int> eliminarTransaccion(int id) => _eliminar(DBKeys.tableTransacciones, id);

  Future<int> actualizarActivo(ActivoFinanciero activo) => _actualizar(DBKeys.tableActivos, activo.toMap());

  Future<int> eliminarActivo(int id) => _eliminar(DBKeys.tableActivos, id);

  Future<List<String>> obtenerTopCategorias() async {
    final db = await baseDatos;
    // Consulta SQL rápida que agrupa y cuenta las veces que aparece cada categoría
    final List<Map<String, dynamic>> resultado = await db.rawQuery('''
      SELECT ${DBKeys.columnCategoria}, COUNT(*) as usos
      FROM ${DBKeys.tableTransacciones}
      WHERE ${DBKeys.columnCategoria} NOT IN (?, ?) AND $_soloVivas
      GROUP BY ${DBKeys.columnCategoria}
      ORDER BY usos DESC
      LIMIT ${AppNumbers.maxCategoriasDefault}
    ''', [AppStrings.categoriaRemanente, AppStrings.categoriaDeficit]);
    return resultado.map((m) => m[DBKeys.columnCategoria] as String).toList();
  }
}
