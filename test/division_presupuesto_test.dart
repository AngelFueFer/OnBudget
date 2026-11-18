import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/division_presupuesto.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/pantallas/formulario_transaccion.dart';
import 'package:presupuesto_familiar/pantallas/selector_vista_presupuesto.dart';

final _inicioPeriodo = DateTime(2026, 10, 1);

Transaccion _mov(double euros, {bool ingreso = false, String? metodo, String categoria = 'Ocio', DateTime? fecha, String concepto = 'x'}) => Transaccion(
      montoEnCentimos: (euros * 100).round(),
      concepto: concepto,
      fecha: fecha ?? DateTime(2026, 10, 5),
      categoria: categoria,
      esIngreso: ingreso,
      tarroDestino: AppStrings.cuentaMensual,
      metodoPago: metodo,
    );

DivisionPresupuesto _calcular(List<Transaccion> movs, VistaPresupuesto vista, {double limite = 0}) => DivisionPresupuesto.calcular(
      transacciones: movs,
      vista: vista,
      metaMensual: 800,
      limiteEfectivo: limite,
      inicioPeriodo: _inicioPeriodo,
    );

Widget _app(Widget hijo, {String idioma = 'es'}) => MaterialApp(
      locale: Locale(idioma),
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
  final nomina = _mov(1000, ingreso: true, categoria: AppStrings.categoriaSalario, concepto: AppStrings.nominaPartePresupuesto);
  final cafeEfectivo = _mov(50, metodo: AppStrings.metodoEfectivo);
  final compraTarjeta = _mov(100, metodo: AppStrings.metodoTarjeta, categoria: 'Supermercado');
  final movimientos = [nomina, cafeEfectivo, compraTarjeta];

  group('DivisionPresupuesto', () {
    test('sin límite de efectivo, la tarjeta es una réplica del total', () {
      final total = _calcular(movimientos, VistaPresupuesto.total);
      final tarjeta = _calcular(movimientos, VistaPresupuesto.tarjeta);
      expect(total.saldo, 850);
      expect(tarjeta.saldo, 850);
      expect(total.meta, 800);
    });

    test('con límite, el efectivo se resta de la tarjeta y tarjeta + efectivo = total', () {
      final total = _calcular(movimientos, VistaPresupuesto.total, limite: 200);
      final efectivo = _calcular(movimientos, VistaPresupuesto.efectivo, limite: 200);
      final tarjeta = _calcular(movimientos, VistaPresupuesto.tarjeta, limite: 200);

      expect(efectivo.saldo, 150); // 200 de límite - 50 gastados en efectivo
      expect(tarjeta.saldo, 700); // 850 - 150 de efectivo que queda
      expect(tarjeta.saldo + efectivo.saldo, total.saldo);

      expect(efectivo.meta, 200);
      expect(tarjeta.meta, 600);
      expect(efectivo.totalGastado, 50);
      expect(tarjeta.totalGastado, 100);
      expect(total.totalGastado, 150);
    });

    test('cada vista lista sus movimientos; sin método de pago cuenta como tarjeta', () {
      final antiguo = _mov(30); // movimiento anterior a los métodos de pago
      final movs = [...movimientos, antiguo];
      expect(_calcular(movs, VistaPresupuesto.efectivo).movimientos, [cafeEfectivo]);
      expect(_calcular(movs, VistaPresupuesto.tarjeta).movimientos, [nomina, compraTarjeta, antiguo]);
      expect(_calcular(movs, VistaPresupuesto.total).movimientos, movs);
    });

    test('el efectivo gastado en periodos anteriores y el remanente no cuentan en la barra', () {
      final efectivoSeptiembre = _mov(40, metodo: AppStrings.metodoEfectivo, fecha: DateTime(2026, 9, 20));
      final remanente = _mov(500, categoria: AppStrings.categoriaRemanente);
      final efectivo = _calcular([...movimientos, efectivoSeptiembre, remanente], VistaPresupuesto.efectivo, limite: 200);
      expect(efectivo.totalGastado, 50);
      expect(efectivo.saldo, 150);
      expect(_calcular([...movimientos, remanente], VistaPresupuesto.total).totalGastado, 150);
    });

    test('un ingreso extra del mes amplía el presupuesto (la nómina automática no)', () {
      final extra = _mov(200, ingreso: true, categoria: 'Salario', concepto: 'Venta bici');
      final total = _calcular([...movimientos, extra], VistaPresupuesto.total);
      expect(total.ingresosExtra, 200);
      expect(total.meta, 1000); // 800 + 200
      expect(total.saldo, 1050);
      // Con límite de efectivo, el extra va a la parte de tarjeta
      expect(_calcular([...movimientos, extra], VistaPresupuesto.tarjeta, limite: 200).meta, 800);
      expect(_calcular([...movimientos, extra], VistaPresupuesto.efectivo, limite: 200).meta, 200);
    });

    test('no amplían el presupuesto los ingresos de meses anteriores ni la cobertura del déficit', () {
      final extraSeptiembre = _mov(300, ingreso: true, fecha: DateTime(2026, 9, 15));
      final cobertura = _mov(120, ingreso: true, categoria: AppStrings.categoriaDeficit, concepto: AppStrings.conceptoDeficit('2026-09'));
      final total = _calcular([...movimientos, extraSeptiembre, cobertura], VistaPresupuesto.total);
      expect(total.ingresosExtra, 0);
      expect(total.meta, 800);
    });
  });

  group('Selector Efectivo / Tarjeta / Total', () {
    for (final idioma in AppStrings.idiomasDisponibles.keys) {
      testWidgets('cabe en la barra superior de un móvil estrecho ($idioma)', (tester) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        VistaPresupuesto? elegida;
        await tester.pumpWidget(_app(
          Scaffold(
            appBar: AppBar(
              leading: IconButton(onPressed: () {}, icon: const Icon(Icons.filter_alt_outlined)),
              centerTitle: true,
              title: SelectorVistaPresupuesto(vista: VistaPresupuesto.total, onCambio: (v) => elegida = v),
              actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.settings))],
            ),
          ),
          idioma: idioma,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull); // sin desbordamientos
        await tester.tap(find.byIcon(Icons.payments));
        expect(elegida, VistaPresupuesto.efectivo);
      });
    }
  });

  testWidgets('orden del selector: Tarjeta a la izquierda, Total en el centro, Efectivo a la derecha', (tester) async {
    await tester.pumpWidget(_app(Scaffold(
      body: Center(child: SelectorVistaPresupuesto(vista: VistaPresupuesto.total, onCambio: (_) {})),
    )));
    await tester.pumpAndSettle();

    final xTarjeta = tester.getCenter(find.text('Tarjeta')).dx;
    final xTotal = tester.getCenter(find.text('Total')).dx;
    final xEfectivo = tester.getCenter(find.text('Efectivo')).dx;
    expect(xTarjeta < xTotal && xTotal < xEfectivo, isTrue);
    // Mismo tamaño que los desplegables de Inversión y Ahorro
    expect(tester.getSize(find.byType(SelectorVistaPresupuesto)), const Size(AppNumbers.anchoSelectorBarra, AppNumbers.altoSelectorBarra));
  });

  group('Formulario desde las vistas', () {
    testWidgets('desde Efectivo, el gasto viene marcado como efectivo', (tester) async {
      SharedPreferences.setMockInitialValues({'tarjetas': '["Visa"]', 'ultimoMetodoPago': 'tarjeta', 'ultimaTarjeta': 'Visa'});
      await tester.pumpWidget(_app(const FormularioTransaccion(metodoPagoPredefinido: AppStrings.metodoEfectivo)));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Efectivo')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Visa')).selected, isFalse);
    });

    testWidgets('desde Tarjeta, el gasto viene con una tarjeta guardada', (tester) async {
      SharedPreferences.setMockInitialValues({'tarjetas': '["Visa", "Revolut"]', 'ultimoMetodoPago': 'efectivo'});
      await tester.pumpWidget(_app(const FormularioTransaccion(metodoPagoPredefinido: AppStrings.metodoTarjeta)));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Visa')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Efectivo')).selected, isFalse);
    });
  });
}
