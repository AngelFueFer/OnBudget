import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/formulario_inversion.dart';
import 'package:presupuesto_familiar/pantallas/formulario_transaccion.dart';

Future<void> _abrir(WidgetTester tester, Widget pantalla) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('es'),
    supportedLocales: AppLocalizations.idiomasSoportados,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: pantalla,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('botón −: formulario de gasto con método de pago y sin interruptor', (tester) async {
    await _abrir(tester, const FormularioTransaccion());
    expect(find.text('Nuevo gasto'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Método de pago'), findsOneWidget);
  });

  testWidgets('botón +: formulario de ingreso sin método de pago', (tester) async {
    await _abrir(tester, const FormularioTransaccion(esIngreso: true));
    expect(find.text('Nuevo ingreso'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Método de pago'), findsNothing);
  });

  testWidgets('desde la pestaña Ahorro, la cuenta por defecto es Ahorro', (tester) async {
    await _abrir(tester, const FormularioTransaccion(esIngreso: true, cuentaPredefinida: 'Ahorro'));
    expect(find.text('Ahorro'), findsOneWidget);
    expect(find.text('Cuenta Mensual'), findsNothing);
  });

  testWidgets('inversión: + es compra y − es venta, sin interruptor', (tester) async {
    await _abrir(tester, const FormularioInversion());
    expect(find.text('Nueva compra'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('inversión: − es venta', (tester) async {
    await _abrir(tester, const FormularioInversion(esCompra: false));
    expect(find.text('Nueva venta'), findsOneWidget);
  });
}
