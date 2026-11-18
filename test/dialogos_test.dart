import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';
import 'package:presupuesto_familiar/utilidades/dialogo_texto.dart';

Widget _app(Widget Function(BuildContext) boton) {
  return MaterialApp(
    locale: const Locale('es'),
    supportedLocales: AppLocalizations.idiomasSoportados,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Builder(builder: boton)),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('diálogo de tarjeta: cerrar tocando fuera no lanza errores', (tester) async {
    await tester.pumpWidget(_app((context) => ElevatedButton(
          onPressed: () => mostrarDialogoNuevaTarjeta(context),
          child: const Text('abrir'),
        )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Últimos 4 dígitos (opcional)'), '12');
    await tester.tapAt(const Offset(5, 5)); // fuera del diálogo
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diálogo de tarjeta: añadir guarda la tarjeta y cierra sin errores', (tester) async {
    String? resultado;
    await tester.pumpWidget(_app((context) => ElevatedButton(
          onPressed: () async => resultado = await mostrarDialogoNuevaTarjeta(context),
          child: const Text('abrir'),
        )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Banco'), 'BBVA');
    await tester.enterText(find.widgetWithText(TextField, 'Últimos 4 dígitos (opcional)'), '1234');
    await tester.pumpAndSettle();
    expect(find.text('Visa BBVA ••1234'), findsWidgets); // vista previa del nombre
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    expect(resultado, 'Visa BBVA ••1234');
    final tarjeta = (await ServicioTarjetas.cargarTarjetas()).single;
    expect(tarjeta.bancoId, 'bbva');
    expect(tarjeta.red, 'Visa');
    expect(tarjeta.tipo, TipoTarjeta.debito);
    expect(tarjeta.ultimos4, '1234');
  });

  testWidgets('diálogo de texto: si la validación falla sigue abierto; tocar fuera devuelve null', (tester) async {
    String? resultado = 'sin tocar';
    await tester.pumpWidget(_app((context) => ElevatedButton(
          onPressed: () async => resultado = await mostrarDialogoTexto(
            context,
            titulo: 'Interés',
            etiqueta: 'TAE',
            textoConfirmar: 'OK',
            validar: (texto) async => double.tryParse(texto) != null,
          ),
          child: const Text('abrir'),
        )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(resultado, isNull);
    expect(tester.takeException(), isNull);
  });
}