import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_importar_extracto.dart';
import 'package:presupuesto_familiar/servicios/detector_pagos.dart';
import 'package:presupuesto_familiar/servicios/detector_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/importador_csv.dart';
import 'package:presupuesto_familiar/servicios/importador_norma43.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_extractos.dart';
import 'package:presupuesto_familiar/servicios/servicio_pagos_detectados.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';

// Extracto Norma 43 de una cuenta BBVA (CCC 0182 0418 75 0200051332):
// saldo inicial 1.000,00; compra de 12,50 con concepto en registro 23; nómina de 1.500,00 sin 23.
String _norma43() {
  String r(String s) => s.padRight(80);
  return [
    r('11' '0182' '0418' '0200051332' '230901' '230930' '2' '00000000100000' '978' '3' '${'JUAN PEREZ'.padRight(26)}'),
    r('22' '    ' '0418' '230905' '230905' '12' '001' '1' '00000000001250' '0000000000' '${'REF000123'.padRight(12)}' '${'TPV'.padRight(16)}'),
    r('23' '01' '${'COMPRA MERCADONA'.padRight(38)}' '${'VALENCIA'.padRight(38)}'),
    r('22' '    ' '0418' '230928' '230928' '02' '001' '2' '00000000150000' '0000000000' '${'NOMINA'.padRight(12)}' '${'EMPRESA SL'.padRight(16)}'),
    r('33' '0182' '0418' '0200051332' '00001' '00000000001250' '00001' '00000000150000' '2' '00000000248750' '978'),
    r('88' '999999999999999999' '000005'),
  ].join('\r\n');
}

Widget _app(Widget hijo) => MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.idiomasSoportados,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: hijo,
    );

void main() {
  late List<Transaccion> guardadas;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    guardadas = [];
    ServicioCuentasAhorro.reasignarMovimientos = (desde, hacia) async {};
    ServicioExtractos.movimientosExistentes = () async => guardadas;
    ServicioExtractos.insertar = (t) async => guardadas.add(t);
    ServicioPagosDetectados.insertar = (t) async => guardadas.add(t);
  });

  group('Norma 43', () {
    test('lee la cuenta, los movimientos con su concepto y el saldo final', () {
      expect(ImportadorNorma43.pareceNorma43(_norma43()), isTrue);
      final cuenta = ImportadorNorma43.leer(_norma43()).single;
      expect(cuenta.entidad, '0182');
      expect(cuenta.oficina, '0418');
      expect(cuenta.numeroCuenta, '0200051332');
      expect(cuenta.saldoFinal, 2487.5);
      expect(cuenta.fechaSaldo, DateTime(2023, 9, 30));

      final [compra, nomina] = cuenta.movimientos;
      expect(compra.fecha, DateTime(2023, 9, 5));
      expect(compra.importe, -12.5);
      expect(compra.concepto, 'COMPRA MERCADONA VALENCIA'); // el 23 sustituye a las referencias
      expect(nomina.importe, 1500);
      expect(nomina.concepto, 'NOMINA EMPRESA SL');
    });

    test('se lee también desde bytes en Latin-1', () {
      final extractos = ServicioExtractos.leer(latin1.encode(_norma43().replaceAll('JUAN PEREZ', 'JOSÉ PEÑA ')));
      expect(extractos.single.movimientos, hasLength(2));
    });

    test('un fichero que no es extracto da error de formato', () {
      expect(() => ServicioExtractos.leer(utf8.encode('hola\nadiós')), throwsA(isA<FormatoExtractoNoValido>()));
    });
  });

  group('CSV', () {
    test('Revolut: columnas en inglés, ignora operaciones revertidas, saldo de la última', () {
      const csv = 'Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance\n'
          'CARD_PAYMENT,Current,2024-03-01 10:00:00,2024-03-02 09:00:00,Starbucks,-4.50,0.00,EUR,COMPLETED,95.50\n'
          'CARD_PAYMENT,Current,2024-03-03 12:00:00,2024-03-03 12:01:00,Amazon,-20.00,0.00,EUR,REVERTED,95.50\n'
          'TOPUP,Current,2024-03-05 08:00:00,2024-03-05 08:00:00,"Top-Up by *1234, thanks",100.00,0.00,EUR,COMPLETED,195.50\n';
      final e = ImportadorCsv.leer(csv);
      expect(e.movimientos.map((m) => m.concepto), ['Starbucks', 'Top-Up by *1234, thanks']);
      expect(e.movimientos.first.importe, -4.5);
      expect(e.saldoFinal, 195.5);
      expect(e.fechaSaldo, DateTime(2024, 3, 5));
    });

    test('banco español: título antes de la cabecera, punto y coma, cargo/abono y orden descendente', () {
      const csv = 'Movimientos de la cuenta ES09 0182 ****\n'
          '\n'
          'Fecha;Concepto;Cargo;Abono;Saldo\n'
          '15/02/2024;Recibo IBERDROLA;45,30;;1.954,70\n'
          '10/02/2024;Transferencia recibida;;2.000,00;2.000,00\n';
      final e = ImportadorCsv.leer(csv);
      expect(e.movimientos.map((m) => m.importe), [-45.3, 2000]);
      expect(e.saldoFinal, 1954.7); // el más reciente es el primero
    });

    test('números y fechas en varios formatos', () {
      expect(ImportadorCsv.leerNumero('1.234,56'), 1234.56);
      expect(ImportadorCsv.leerNumero('1,234.56'), 1234.56);
      expect(ImportadorCsv.leerNumero('-12,5 €'), -12.5);
      expect(ImportadorCsv.leerNumero('12.500'), 12500);
      expect(ImportadorCsv.leerNumero(''), isNull);
      expect(ImportadorCsv.leerFecha('2024-03-01T10:00'), DateTime(2024, 3, 1));
      expect(ImportadorCsv.leerFecha('05.04.2024'), DateTime(2024, 4, 5));
      expect(ImportadorCsv.leerFecha('05/04/24'), DateTime(2024, 4, 5));
      expect(ImportadorCsv.leerFecha('Starbucks'), isNull);
    });

    test('sin columnas de fecha e importe da error de formato', () {
      expect(() => ImportadorCsv.leer('a;b\n1;2'), throwsA(isA<FormatoExtractoNoValido>()));
    });
  });

  group('ServicioExtractos', () {
    test('sugiere categoría por el concepto', () {
      MovimientoExtracto m(String c, double i) => MovimientoExtracto(fecha: DateTime(2024), concepto: c, importe: i);
      expect(ServicioExtractos.sugerirCategoria(m('COMPRA MERCADONA VALENCIA', -12)), 'Supermercado');
      expect(ServicioExtractos.sugerirCategoria(m('Recibo IBERDROLA CLIENTES', -45)), 'Luz');
      expect(ServicioExtractos.sugerirCategoria(m('NÓMINA EMPRESA SL', 1500)), AppStrings.categoriaSalario);
      expect(ServicioExtractos.sugerirCategoria(m('Bizum Ana', -10)), AppStrings.categoriaGeneral);
    });

    test('reconoce movimientos ya importados', () async {
      final mov = MovimientoExtracto(fecha: DateTime(2023, 9, 5), concepto: 'COMPRA MERCADONA', importe: -12.5);
      await ServicioExtractos.importar([(mov, 'Supermercado')]);
      expect(guardadas.single.tarroDestino, AppStrings.cuentaMensual);
      expect(guardadas.single.montoEnCentimos, 1250);
      expect(guardadas.single.esIngreso, isFalse);
      expect(ServicioExtractos.yaImportado(mov, guardadas), isTrue);
      expect(ServicioExtractos.yaImportado(MovimientoExtracto(fecha: DateTime(2023, 9, 6), concepto: 'COMPRA MERCADONA', importe: -12.5), guardadas), isFalse);
    });
  });

  group('Historial de saldos', () {
    test('se guarda un apunte por día y un extracto antiguo no pisa el saldo actual', () async {
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA', tipo: TipoCuenta.corriente, saldo: 1000);
      await ServicioCuentasAhorro.actualizarSaldo(cuenta.id, 1100);
      await ServicioCuentasAhorro.actualizarSaldo(cuenta.id, 500, fecha: DateTime(2023, 1, 31));

      final actual = (await ServicioCuentasAhorro.cargarTodas()).single;
      expect(actual.saldo, 1100);
      final historial = await ServicioCuentasAhorro.historial(cuenta.id);
      expect(historial.map((a) => a.saldo), [500, 1100]); // ordenado y hoy solo cuenta el último

      await ServicioCuentasAhorro.eliminar(cuenta.id);
      expect(await ServicioCuentasAhorro.historial(cuenta.id), isEmpty);
    });

    test('encuentra la cuenta por el CCC del extracto', () async {
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA', tipo: TipoCuenta.corriente, iban: 'ES0901820418750200051332');
      expect((await ServicioCuentasAhorro.buscarPorCcc('0182', '0418', '0200051332'))!.id, cuenta.id);
      expect(await ServicioCuentasAhorro.buscarPorCcc('0182', '0418', '0000000000'), isNull);
    });
  });

  testWidgets('previsualización: sin elegir nada solo actualiza el saldo; elegir gastos importa la compra', (tester) async {
    final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA', tipo: TipoCuenta.corriente);
    final extracto = ImportadorNorma43.leer(_norma43()).single;

    await tester.pumpWidget(_app(PantallaImportarExtracto(cuenta: cuenta, extracto: extracto)));
    await tester.pumpAndSettle();
    expect(find.text('2 movimientos en el extracto'), findsOneWidget);
    expect(find.text('Supermercado'), findsOneWidget);
    expect(find.text('Solo el saldo'), findsOneWidget);

    await tester.tap(find.text('Elegir gastos'));
    await tester.pumpAndSettle();
    expect(find.text('Importar 1'), findsOneWidget);
    await tester.tap(find.text('Importar 1'));
    await tester.pumpAndSettle();

    expect(guardadas.single.concepto, 'COMPRA MERCADONA VALENCIA');
    expect(guardadas.single.categoria, 'Supermercado');
    expect((await ServicioCuentasAhorro.cargarTodas()).single.saldo, 2487.5);
  });

  group('Notificaciones bancarias', () {
    const bbva = 'com.bbva.bbvacontigo';
    const revolut = 'com.revolut.revolut';
    final ahora = DateTime(2024, 5, 10, 13, 45);

    test('detecta pagos con importe, comercio y tarjeta', () {
      final p1 = DetectorPagos.detectar(bbva, 'BBVA', 'Compra de 12,50 € en MERCADONA con tu tarjeta ••1234', ahora: ahora)!;
      expect((p1.importe, p1.comercio, p1.ultimos4, p1.bancoId), (12.5, 'MERCADONA', '1234', 'bbva'));

      final p2 = DetectorPagos.detectar(revolut, 'Starbucks', 'Paid €4.50 with Visa ••9876', ahora: ahora)!;
      expect((p2.importe, p2.comercio, p2.ultimos4), (4.5, 'Starbucks', '9876'));

      final p3 = DetectorPagos.detectar(revolut, 'Payment', 'You spent €1,234.00 at Apple Store', ahora: ahora)!;
      expect((p3.importe, p3.comercio), (1234.0, 'Apple Store'));
    });

    test('detecta pagos de PayPal y otras apps de pago, y Bizum enviados', () {
      const paypal = 'com.paypal.android.p2pmobile';
      final p1 = DetectorPagos.detectar(paypal, 'PayPal', 'Has pagado 10,00 € EUR a Amazon', ahora: ahora)!;
      expect((p1.importe, p1.comercio, p1.bancoId), (10.0, 'Amazon', 'paypal'));

      final p2 = DetectorPagos.detectar(paypal, 'PayPal', 'You sent €25.00 EUR to John Smith', ahora: ahora)!;
      expect((p2.importe, p2.comercio), (25.0, 'John Smith'));

      final p3 = DetectorPagos.detectar('com.imaginecurve.curve.prod', 'Curve', 'Paid €7.20 at Lidl', ahora: ahora)!;
      expect((p3.importe, p3.comercio, p3.bancoId), (7.2, 'Lidl', 'curve'));

      final p4 = DetectorPagos.detectar(bbva, 'BBVA', 'Has enviado un Bizum de 15,00 € a Ana', ahora: ahora)!;
      expect((p4.importe, p4.comercio), (15.0, 'Ana'));

      expect(DetectorPagos.detectar(paypal, 'PayPal', 'Has recibido 20,00 € EUR de Juan'), isNull);
      expect(DetectorPagos.detectar(bbva, 'BBVA', 'Has recibido un Bizum de 15,00 € de Ana'), isNull);
    });

    test('ignora ingresos, devoluciones, otras apps y textos sin importe', () {
      expect(DetectorPagos.detectar(bbva, 'BBVA', 'Has recibido una transferencia de 100,00 €'), isNull);
      expect(DetectorPagos.detectar(revolut, 'Refund', 'Refund of €4.50 from Amazon'), isNull);
      expect(DetectorPagos.detectar('com.whatsapp', 'Ana', 'Pago de 10 € en el bar'), isNull);
      expect(DetectorPagos.detectar(bbva, 'BBVA', 'Tu pago está disponible en la app'), isNull);
    });

    test('las apps bancarias también proponen tarjetas con el nombre del banco', () {
      expect(DetectorTarjetas.detectar(bbva, 'BBVA', 'Compra de 12,50 € con Visa ••1234'), 'Visa BBVA ••1234');
      expect(DetectorTarjetas.detectar(revolut, 'Starbucks', 'Paid €4.50 ••9876'), 'Revolut ••9876');
    });

    test('un pago se propone una vez y al confirmarlo se añade como gasto con su tarjeta', () async {
      await ServicioTarjetas.anadir('Visa BBVA ••1234');
      final pago = DetectorPagos.detectar(bbva, 'BBVA', 'Compra de 12,50 € en MERCADONA con tarjeta ••1234', ahora: ahora)!;
      expect(await ServicioPagosDetectados.anadir(pago), isTrue);
      expect(await ServicioPagosDetectados.anadir(pago), isFalse); // notificación repetida
      expect(ServicioPagosDetectados.pendientes.value, hasLength(1));

      await ServicioPagosDetectados.confirmar(pago);
      expect(ServicioPagosDetectados.pendientes.value, isEmpty);
      final gasto = guardadas.single;
      expect(gasto.concepto, 'MERCADONA');
      expect(gasto.categoria, 'Supermercado');
      expect(gasto.montoEnCentimos, 1250);
      expect(gasto.metodoPago, AppStrings.metodoTarjeta);
      expect(gasto.tarjeta, 'Visa BBVA ••1234');
    });
  });
}
