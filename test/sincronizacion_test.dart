import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/modelos/activo.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/sincronizacion/fusion.dart';
import 'package:presupuesto_familiar/sincronizacion/identificadores.dart';
import 'package:presupuesto_familiar/sincronizacion/reloj_hibrido.dart';

Transaccion _gasto({int? id, int monto = 1250, String categoria = 'Comida', String? cuentaAhorro, String tarro = 'Gastos'}) =>
    Transaccion(
      id: id,
      montoEnCentimos: monto,
      concepto: 'Mercadona',
      fecha: DateTime(2026, 11, 5),
      categoria: categoria,
      esIngreso: false,
      tarroDestino: tarro,
      cuentaAhorro: cuentaAhorro,
    );

void main() {
  group('Reloj híbrido', () {
    test('cada marca es mayor que la anterior aunque la hora no avance', () {
      final reloj = RelojHibrido('a', ahora: () => DateTime.fromMillisecondsSinceEpoch(1000));
      final m1 = reloj.siguiente();
      final m2 = reloj.siguiente();
      expect(RelojHibrido.esPosterior(m2, m1), isTrue);
    });

    test('si la hora del móvil retrocede, las marcas siguen avanzando', () {
      var ms = 5000;
      final reloj = RelojHibrido('a', ahora: () => DateTime.fromMillisecondsSinceEpoch(ms));
      final m1 = reloj.siguiente();
      ms = 1000;
      expect(RelojHibrido.esPosterior(reloj.siguiente(), m1), isTrue);
    });

    test('tras recibir una marca adelantada, lo siguiente local queda por delante', () {
      final lento = RelojHibrido('a', ahora: () => DateTime.fromMillisecondsSinceEpoch(1000));
      final rapido = RelojHibrido('b', ahora: () => DateTime.fromMillisecondsSinceEpoch(90000));
      final remota = rapido.siguiente();
      lento.recibir(remota);
      expect(RelojHibrido.esPosterior(lento.siguiente(), remota), isTrue);
    });

    test('leer recupera el dispositivo aunque sea un uuid con guiones', () {
      final id = nuevoUuid();
      final marca = RelojHibrido(id, ahora: () => DateTime.fromMillisecondsSinceEpoch(42)).siguiente();
      final leida = RelojHibrido.leer(marca)!;
      expect(leida.ms, 42);
      expect(leida.dispositivo, id);
      expect(RelojHibrido.leer('basura'), isNull);
    });

    test('null nunca es posterior y cualquier marca es posterior a null', () {
      expect(RelojHibrido.esPosterior(null, 'x'), isFalse);
      expect(RelojHibrido.esPosterior('x', null), isTrue);
    });
  });

  group('Identificadores', () {
    test('nuevoUuid tiene formato v4 y no se repite', () {
      final formato = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = List.generate(500, (_) => nuevoUuid());
      expect(ids.every(formato.hasMatch), isTrue);
      expect(ids.toSet().length, ids.length);
      expect(formato.hasMatch(nuevoUuid(Random(1))), isTrue);
    });
  });

  group('Fusión campo a campo', () {
    Map<String, Object?> fila(Map<String, Object?> datos, Map<String, String> relojes) => {
          DBKeys.columnUuid: 'u1',
          ...datos,
          DBKeys.columnRelojes: jsonEncode(relojes),
        };

    test('cambios en campos distintos de dos móviles se conservan los dos', () {
      final local = fila({DBKeys.columnMonto: 2000, DBKeys.columnCategoria: 'Comida'},
          {DBKeys.columnMonto: '0000000000000002-0000-a', DBKeys.columnCategoria: '0000000000000001-0000-a'});
      final remota = fila({DBKeys.columnMonto: 1000, DBKeys.columnCategoria: 'Ocio'},
          {DBKeys.columnMonto: '0000000000000001-0000-b', DBKeys.columnCategoria: '0000000000000003-0000-b'});
      final r = fusionarFila(local: local, remota: remota);
      expect(r[DBKeys.columnMonto], 2000);
      expect(r[DBKeys.columnCategoria], 'Ocio');
      expect(r[DBKeys.columnModificado], '0000000000000003-0000-b');
      expect(r[DBKeys.columnDispositivo], 'b');
    });

    test('fila nueva: se copia entera', () {
      final remota = fila({DBKeys.columnMonto: 500}, {DBKeys.columnMonto: '0000000000000001-0000-b'});
      final r = fusionarFila(local: null, remota: remota);
      expect(r[DBKeys.columnMonto], 500);
      expect(r[DBKeys.columnUuid], 'u1');
    });

    test('relojes ilegibles no rompen la fusión', () {
      expect(leerRelojes('{no json'), isEmpty);
      expect(leerRelojes(null), isEmpty);
    });

    test('marcarCambios solo sella los campos que cambian', () {
      final relojes = marcarCambios({'a': 1, 'b': 2}, {'a': 1, 'b': 3, DBKeys.columnId: 9}, {'a': 'viejo'}, 'nuevo');
      expect(relojes, {'a': 'viejo', 'b': 'nuevo'});
    });
  });

  group('Base de datos (v6)', () {
    late Directory carpeta;

    setUpAll(() {
      sqfliteFfiInit();
      DBHelper.fabricaBaseDatos = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      carpeta = await Directory.systemTemp.createTemp('presupuesto_test');
      DBHelper.rutaBaseDatos = p.join(carpeta.path, 'presupuesto.db');
    });

    tearDown(() async {
      await DBHelper().cerrar();
      await carpeta.delete(recursive: true);
    });

    test('la migración desde v5 conserva los datos y da uuid a cada fila', () async {
      final v5 = await databaseFactoryFfi.openDatabase(DBHelper.rutaBaseDatos!,
          options: OpenDatabaseOptions(
            version: 5,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE ${DBKeys.tableTransacciones}(${DBKeys.columnId} INTEGER PRIMARY KEY AUTOINCREMENT, '
                  '${DBKeys.columnMonto} INTEGER, ${DBKeys.columnConcepto} TEXT, ${DBKeys.columnFecha} TEXT, '
                  '${DBKeys.columnCategoria} TEXT, ${DBKeys.columnEsIngreso} INTEGER, ${DBKeys.columnTarro} TEXT, '
                  '${DBKeys.columnMetodoPago} TEXT, ${DBKeys.columnTarjeta} TEXT, ${DBKeys.columnCuentaAhorro} TEXT, '
                  '${DBKeys.columnTiquet} TEXT)');
              await db.execute('CREATE TABLE ${DBKeys.tableActivos}(${DBKeys.columnId} INTEGER PRIMARY KEY AUTOINCREMENT, '
                  '${DBKeys.columnTicker} TEXT, ${DBKeys.columnCantidad} REAL, ${DBKeys.columnPrecioCompra} REAL, '
                  '${DBKeys.columnTipo} TEXT, ${DBKeys.columnNombre} TEXT, ${DBKeys.columnIsin} TEXT)');
            },
          ));
      final mapa = _gasto().toMap()..remove(DBKeys.columnId);
      await v5.insert(DBKeys.tableTransacciones, mapa);
      await v5.insert(DBKeys.tableTransacciones, {...mapa, DBKeys.columnMonto: 300});
      await v5.insert(DBKeys.tableActivos, {DBKeys.columnTicker: 'SAN.MC', DBKeys.columnCantidad: 10.0, DBKeys.columnPrecioCompra: 3.5});
      await v5.close();

      final db = DBHelper();
      final transacciones = await db.obtenerTransacciones();
      expect(transacciones.map((t) => t.montoEnCentimos), containsAll([1250, 300]));
      expect((await db.obtenerActivos()).single.ticker, 'SAN.MC');

      final crudas = await (await db.baseDatos).query(DBKeys.tableTransacciones);
      final uuids = crudas.map((f) => f[DBKeys.columnUuid]).toSet();
      expect(uuids.length, 2);
      expect(uuids.contains(null), isFalse);
      expect(leerRelojes(crudas.first[DBKeys.columnRelojes]), contains(DBKeys.columnMonto));
      expect(await (await db.baseDatos).getVersion(), DBHelper.versionBaseDatos);
    });

    test('insertar, editar y borrar apuntan cambios y el borrado es lógico', () async {
      final db = DBHelper();
      final id = await db.insertarTransaccion(_gasto());
      await db.actualizarTransaccion(_gasto(id: id, monto: 999));
      await db.eliminarTransaccion(id);

      expect(await db.obtenerTransacciones(), isEmpty);
      final cruda = (await (await db.baseDatos).query(DBKeys.tableTransacciones)).single;
      expect(cruda[DBKeys.columnBorrado], 1);
      expect(cruda[DBKeys.columnMonto], 999);

      final pendientes = await db.obtenerCambiosPendientes();
      expect(pendientes.filas.length, 1, reason: 'Varios cambios de la misma fila viajan como uno');
      expect(pendientes.hastaId, 3);
      await db.descartarCambiosHasta(pendientes.hastaId);
      expect((await db.obtenerCambiosPendientes()).filas, isEmpty);
    });

    test('editar solo sella los campos modificados', () async {
      final db = DBHelper();
      final id = await db.insertarTransaccion(_gasto());
      final antes = leerRelojes((await (await db.baseDatos).query(DBKeys.tableTransacciones)).single[DBKeys.columnRelojes]);
      await db.actualizarTransaccion(_gasto(id: id, monto: 1));
      final despues = leerRelojes((await (await db.baseDatos).query(DBKeys.tableTransacciones)).single[DBKeys.columnRelojes]);
      expect(despues[DBKeys.columnCategoria], antes[DBKeys.columnCategoria]);
      expect(RelojHibrido.esPosterior(despues[DBKeys.columnMonto], antes[DBKeys.columnMonto]), isTrue);
    });

    test('reinsertar con un id existente edita la fila en vez de duplicarla', () async {
      final db = DBHelper();
      final id = await db.insertarTransaccion(_gasto());
      await db.insertarTransaccion(_gasto(id: id, monto: 42));
      final todas = await db.obtenerTransacciones();
      expect(todas.single.montoEnCentimos, 42);
    });

    test('reasignar cuenta de ahorro sella cada movimiento', () async {
      final db = DBHelper();
      await db.insertarTransaccion(_gasto(tarro: AppStrings.ahorro, cuentaAhorro: 'c1'));
      await db.insertarTransaccion(_gasto(tarro: AppStrings.ahorro, cuentaAhorro: 'c1'));
      await db.descartarCambiosHasta((await db.obtenerCambiosPendientes()).hastaId);
      expect(await db.reasignarCuentaAhorro('c1', 'c2'), 2);
      expect((await db.obtenerTransacciones()).every((t) => t.cuentaAhorro == 'c2'), isTrue);
      expect((await db.obtenerCambiosPendientes()).filas.length, 2);
    });

    test('los activos también se sincronizan', () async {
      final db = DBHelper();
      final id = await db.insertarActivo(ActivoFinanciero(ticker: 'aapl.us', cantidad: 1, precioCompra: 100));
      await db.eliminarActivo(id);
      expect(await db.obtenerActivos(), isEmpty);
      expect((await db.obtenerCambiosPendientes()).filas.single.tabla, DBKeys.tableActivos);
    });

    test('una fila remota nueva se inserta y no vuelve a la cola', () async {
      final db = DBHelper();
      await db.aplicarFilaRemota(DBKeys.tableTransacciones, {
        ..._gasto().toMap()..remove(DBKeys.columnId),
        DBKeys.columnUuid: 'remota-1',
        DBKeys.columnBorrado: 0,
        DBKeys.columnRelojes: jsonEncode({DBKeys.columnMonto: '0000000000000001-0000-otro'}),
        DBKeys.columnModificado: '0000000000000001-0000-otro',
        'campoDeUnaVersionFutura': 'x',
      });
      expect((await db.obtenerTransacciones()).single.montoEnCentimos, 1250);
      expect((await db.obtenerCambiosPendientes()).filas, isEmpty);
    });

    test('una edición posterior a un borrado remoto recupera la fila', () async {
      var ms = 1000;
      DBHelper.ahora = () => DateTime.fromMillisecondsSinceEpoch(ms);
      addTearDown(() => DBHelper.ahora = DateTime.now);
      final db = DBHelper();
      final id = await db.insertarTransaccion(_gasto());
      final uuid = (await (await db.baseDatos).query(DBKeys.tableTransacciones)).single[DBKeys.columnUuid];

      // Otro móvil borra en el milisegundo 2000
      const marcaBorrado = '000000000002000-0000-otro';
      await db.aplicarFilaRemota(DBKeys.tableTransacciones, {
        DBKeys.columnUuid: uuid,
        DBKeys.columnBorrado: 1,
        DBKeys.columnRelojes: jsonEncode({DBKeys.columnBorrado: marcaBorrado}),
        DBKeys.columnModificado: marcaBorrado,
      });
      expect(await db.obtenerTransacciones(), isEmpty);

      // Una edición remota anterior al borrado no la recupera...
      await db.aplicarFilaRemota(DBKeys.tableTransacciones, {
        DBKeys.columnUuid: uuid,
        DBKeys.columnBorrado: 0,
        DBKeys.columnRelojes: jsonEncode({DBKeys.columnBorrado: '000000000001500-0000-otro'}),
      });
      expect(await db.obtenerTransacciones(), isEmpty);

      // ...pero una edición local posterior sí
      ms = 3000;
      await db.actualizarTransaccion(_gasto(id: id, monto: 7));
      expect((await db.obtenerTransacciones()).single.montoEnCentimos, 7);
    });
  });
}
