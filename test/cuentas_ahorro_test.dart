import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/formulario_transaccion.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';

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
  // Registra las reasignaciones de movimientos en lugar de tocar la base de datos
  late List<(String?, String?)> reasignaciones;
  setUp(() {
    SharedPreferences.setMockInitialValues({'tasaAhorro': 2.5});
    reasignaciones = [];
    ServicioCuentasAhorro.reasignarMovimientos = (desde, hacia) async => reasignaciones.add((desde, hacia));
  });

  group('ServicioCuentasAhorro', () {
    test('por defecto no hay cuentas', () async {
      expect(await ServicioCuentasAhorro.cargar(), isEmpty);
      expect(await ServicioCuentasAhorro.principal(), isNull);
    });

    test('la primera es la principal, hereda el interés y recibe el ahorro existente', () async {
      final ing = await ServicioCuentasAhorro.anadir(' Cuenta Naranja ', 'ING');
      final bbva = await ServicioCuentasAhorro.anadir('Ahorro', 'BBVA');

      expect(ing.principal, isTrue);
      expect(ing.tasa, 2.5);
      expect(ing.nombreCompleto, 'ING · Cuenta Naranja');
      expect(bbva.principal, isFalse);
      expect(bbva.tasa, 0);
      expect(reasignaciones, [(null, ing.id)]); // solo al crear la primera
      expect((await ServicioCuentasAhorro.principal())!.id, ing.id);
    });

    test('se puede cambiar la principal y editar el interés de cada cuenta', () async {
      final ing = await ServicioCuentasAhorro.anadir('Naranja', 'ING');
      final bbva = await ServicioCuentasAhorro.anadir('Ahorro', 'BBVA');
      await ServicioCuentasAhorro.marcarPrincipal(bbva.id);
      await ServicioCuentasAhorro.editar(ing.id, tasa: 3);

      final cuentas = await ServicioCuentasAhorro.cargar();
      expect(cuentas.where((c) => c.principal).single.id, bbva.id);
      expect(cuentas.firstWhere((c) => c.id == ing.id).tasa, 3);
    });

    test('al borrar la principal, la siguiente pasa a serlo y recibe sus movimientos', () async {
      final ing = await ServicioCuentasAhorro.anadir('Naranja', 'ING');
      final bbva = await ServicioCuentasAhorro.anadir('Ahorro', 'BBVA');
      reasignaciones.clear();

      await ServicioCuentasAhorro.eliminar(ing.id);
      final cuentas = await ServicioCuentasAhorro.cargar();
      expect(cuentas.single.id, bbva.id);
      expect(cuentas.single.principal, isTrue);
      expect(reasignaciones, [(ing.id, bbva.id)]);
    });

    test('al borrar la última, sus movimientos se quedan sin cuenta', () async {
      final ing = await ServicioCuentasAhorro.anadir('Naranja', 'ING');
      reasignaciones.clear();
      await ServicioCuentasAhorro.eliminar(ing.id);
      expect(await ServicioCuentasAhorro.cargar(), isEmpty);
      expect(reasignaciones, [(ing.id, null)]);
    });
  });

  group('Cuentas corrientes e IBAN', () {
    test('las cuentas guardadas antes de existir el tipo son de ahorro', () async {
      SharedPreferences.setMockInitialValues({
        'cuentasAhorro': '[{"id":"1","nombre":"Naranja","banco":"ING","principal":true,"tasa":2}]',
      });
      final cuentas = await ServicioCuentasAhorro.cargarTodas();
      expect(cuentas.single.tipo, TipoCuenta.ahorro);
      expect(cuentas.single.iban, isNull);
      expect(await ServicioCuentasAhorro.cargar(), hasLength(1));
    });

    test('una corriente no es principal ni aparece entre las de ahorro', () async {
      final corriente = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA',
          tipo: TipoCuenta.corriente, iban: 'es09 0182 0418 7502 0005 1332', bancoId: 'bbva', saldo: 1200);
      expect(corriente.principal, isFalse);
      expect(corriente.iban, 'ES0901820418750200051332');
      expect(corriente.saldo, 1200);
      expect(corriente.saldoFecha, isNotNull);
      expect(reasignaciones, isEmpty);
      expect(await ServicioCuentasAhorro.cargar(), isEmpty);

      // La primera de ahorro sigue siendo la principal aunque ya exista una corriente
      final ahorro = await ServicioCuentasAhorro.anadir('Naranja', 'ING');
      expect(ahorro.principal, isTrue);
      expect(reasignaciones, [(null, ahorro.id)]);

      await ServicioCuentasAhorro.marcarPrincipal(ahorro.id);
      expect((await ServicioCuentasAhorro.cargarTodas()).where((c) => c.principal).single.id, ahorro.id);
    });

    test('borrar una corriente no mueve movimientos; saldo e IBAN se editan', () async {
      final corriente = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA', tipo: TipoCuenta.corriente);
      await ServicioCuentasAhorro.actualizarSaldo(corriente.id, 350.5);
      await ServicioCuentasAhorro.editar(corriente.id, iban: 'ES0901820418750200051332');
      var guardada = (await ServicioCuentasAhorro.cargarTodas()).single;
      expect(guardada.saldo, 350.5);
      expect(guardada.iban, 'ES0901820418750200051332');

      await ServicioCuentasAhorro.editar(corriente.id, iban: '');
      guardada = (await ServicioCuentasAhorro.cargarTodas()).single;
      expect(guardada.iban, isNull);

      await ServicioCuentasAhorro.eliminar(corriente.id);
      expect(await ServicioCuentasAhorro.cargarTodas(), isEmpty);
      expect(reasignaciones, isEmpty);
    });
  });

  testWidgets('al escribir el IBAN se reconoce el banco y se propone el nombre', (tester) async {
    CuentaAhorro? creada;
    await tester.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => creada = await mostrarDialogoCuentaAhorro(context, tipo: TipoCuenta.corriente),
          child: const Text('abrir'),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'IBAN (opcional)'), 'es0901820418750200051332');
    await tester.pumpAndSettle();
    expect(find.text('ES09 0182 0418 7502 0005 1332'), findsOneWidget);
    expect(find.text('Cuenta BBVA'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(creada!.bancoId, 'bbva');
    expect(creada!.banco, 'BBVA');
    expect(creada!.tipo, TipoCuenta.corriente);
    expect(creada!.iban, 'ES0901820418750200051332');
    expect(tester.takeException(), isNull);
  });

  testWidgets('un IBAN incorrecto muestra el error y no guarda', (tester) async {
    CuentaAhorro? creada;
    await tester.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => creada = await mostrarDialogoCuentaAhorro(context),
          child: const Text('abrir'),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'IBAN (opcional)'), 'ES9921000418450200051332');
    await tester.enterText(find.widgetWithText(TextField, 'Nombre de la cuenta'), 'Ahorro');
    await tester.pumpAndSettle();
    expect(find.text('IBAN no válido: revisa los dígitos'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(creada, isNull);
    expect(find.text('Guardar'), findsOneWidget); // el diálogo sigue abierto
  });

  testWidgets('el diálogo crea la cuenta con nombre y banco', (tester) async {
    CuentaAhorro? creada;
    await tester.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => creada = await mostrarDialogoCuentaAhorro(context),
          child: const Text('abrir'),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nombre de la cuenta'), 'Cuenta Naranja');
    await tester.enterText(find.widgetWithText(TextField, 'Banco'), 'ING');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(creada!.nombreCompleto, 'ING · Cuenta Naranja');
    expect(creada!.principal, isTrue);
    expect(creada!.bancoId, 'ing'); // escrito a mano, pero coincide con el catálogo
    expect(tester.takeException(), isNull);
  });

  group('Formulario', () {
    testWidgets('en Ahorro aparece el desplegable con la cuenta elegida', (tester) async {
      await ServicioCuentasAhorro.anadir('Naranja', 'ING');
      final bbva = await ServicioCuentasAhorro.anadir('Ahorro', 'BBVA');

      await tester.pumpWidget(_app(FormularioTransaccion(
        esIngreso: true,
        cuentaPredefinida: AppStrings.ahorro,
        cuentaAhorroPredefinida: bbva.id,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta de ahorro'), findsOneWidget);
      expect(find.text('BBVA · Ahorro'), findsOneWidget);
    });

    testWidgets('en la Cuenta Mensual o sin cuentas de ahorro no aparece', (tester) async {
      await tester.pumpWidget(_app(const FormularioTransaccion(esIngreso: true, cuentaPredefinida: AppStrings.ahorro)));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta de ahorro'), findsNothing);
    });
  });
}
