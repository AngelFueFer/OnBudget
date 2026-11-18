import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/filtro_movimientos.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/pantallas/hoja_filtros.dart';

Transaccion _t(String categoria, double euros, DateTime fecha) => Transaccion(
      montoEnCentimos: (euros * 100).round(),
      concepto: 'x',
      fecha: fecha,
      categoria: categoria,
      esIngreso: false,
      tarroDestino: 'Cuenta Mensual',
    );

void main() {
  group('FiltroMovimientos', () {
    final super10 = _t('Supermercado', 10, DateTime(2026, 10, 1, 9));
    final ocio50 = _t('Ocio', 50, DateTime(2026, 10, 15, 23, 30));
    final hogar200 = _t('Hogar', 200, DateTime(2026, 9, 20));
    final todos = [super10, ocio50, hogar200];

    test('vacío no filtra nada', () {
      expect(FiltroMovimientos.vacio.activo, isFalse);
      expect(todos.where(FiltroMovimientos.vacio.cumple), todos);
    });

    test('por categorías', () {
      const filtro = FiltroMovimientos(categorias: {'Ocio', 'Hogar'});
      expect(todos.where(filtro.cumple), [ocio50, hogar200]);
    });

    test('por importe mínimo, máximo o ambos (inclusivos)', () {
      expect(todos.where(const FiltroMovimientos(importeMinimo: 50).cumple), [ocio50, hogar200]);
      expect(todos.where(const FiltroMovimientos(importeMaximo: 50).cumple), [super10, ocio50]);
      expect(todos.where(const FiltroMovimientos(importeMinimo: 20, importeMaximo: 100).cumple), [ocio50]);
    });

    test('por fechas: incluye los días completos de inicio y fin', () {
      final filtro = FiltroMovimientos(fechas: DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 15)));
      expect(todos.where(filtro.cumple), [super10, ocio50]); // ocio50 es a las 23:30 del último día
    });

    test('combina criterios y cuenta los activos', () {
      final filtro = FiltroMovimientos(
        categorias: const {'Supermercado', 'Ocio'},
        importeMinimo: 20,
        fechas: DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31)),
      );
      expect(filtro.criteriosActivos, 3);
      expect(todos.where(filtro.cumple), [ocio50]);
      expect(filtro.sinImporte().criteriosActivos, 2);
      expect(filtro.sinCategorias().sinFechas().categorias, isEmpty);
    });
  });

  test('en Inversión filtra por activo (ticker) e importe de la operación', () {
    const filtro = FiltroMovimientos(categorias: {'SAN.MC'}, importeMinimo: 100);
    expect(filtro.cumpleCategoriaEImporte('SAN.MC', 450), isTrue);
    expect(filtro.cumpleCategoriaEImporte('SAN.MC', 40), isFalse);
    expect(filtro.cumpleCategoriaEImporte('AAPL.US', 450), isFalse);
  });

  group('Hoja de filtros', () {
    Future<Future<FiltroMovimientos?>> abrir(WidgetTester tester, FiltroMovimientos inicial) async {
      late Future<FiltroMovimientos?> resultado;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.idiomasSoportados,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => resultado = mostrarHojaFiltros(
                context,
                filtroActual: inicial,
                categoriasDisponibles: const ['Ocio', 'Supermercado'],
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return resultado;
    }

    testWidgets('elegir categoría e importes (al revés) y aplicar', (tester) async {
      final resultado = await abrir(tester, FiltroMovimientos.vacio);

      await tester.tap(find.text('Ocio'));
      await tester.enterText(find.widgetWithText(TextField, 'Mínimo'), '100');
      await tester.enterText(find.widgetWithText(TextField, 'Máximo'), '20,5');
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      final filtro = await resultado;
      expect(filtro!.categorias, {'Ocio'});
      expect(filtro.importeMinimo, 20.5); // se intercambian si se escriben al revés
      expect(filtro.importeMaximo, 100);
      expect(tester.takeException(), isNull);
    });

    testWidgets('limpiar deja el filtro vacío', (tester) async {
      final resultado = await abrir(tester, const FiltroMovimientos(categorias: {'Ocio'}, importeMinimo: 5));

      await tester.tap(find.text('Limpiar'));
      await tester.ensureVisible(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect((await resultado)!.activo, isFalse);
    });

    testWidgets('cerrar sin aplicar no cambia nada y no lanza errores', (tester) async {
      final resultado = await abrir(tester, FiltroMovimientos.vacio);
      await tester.enterText(find.widgetWithText(TextField, 'Mínimo'), '10');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(await resultado, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
