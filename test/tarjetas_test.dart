import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/detector_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_notificaciones.dart';
import 'package:presupuesto_familiar/servicios/servicio_pagos_detectados.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';

const _google = 'com.google.android.apps.walletnfcrel';
const _samsung = 'com.samsung.android.spay';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DetectorTarjetas', () {
    test('detecta red y últimos 4 dígitos en distintos formatos e idiomas', () {
      expect(DetectorTarjetas.detectar(_google, 'Mercadona', '12,50 € con Visa ••1234'), 'Visa ••1234');
      expect(DetectorTarjetas.detectar(_google, 'Starbucks', '\$4.50 with Mastercard •••• 9876'), 'Mastercard ••9876');
      expect(DetectorTarjetas.detectar(_samsung, 'Pago realizado', 'Tarjeta Visa terminada en 4321'), 'Visa ••4321');
      expect(DetectorTarjetas.detectar(_samsung, 'Paiement', 'Carte Mastercard se terminant par 1111'), 'Mastercard ••1111');
      expect(DetectorTarjetas.detectar(_google, 'Zahlung', 'Maestro endet auf 2222'), 'Maestro ••2222');
      expect(DetectorTarjetas.detectar(_google, 'Amazon', 'American Express ****3333'), 'Amex ••3333');
    });

    test('sin red reconocible usa el nombre del wallet', () {
      expect(DetectorTarjetas.detectar(_samsung, 'Pago', '5,00 € · ••5555'), 'Samsung Wallet ••5555');
    });

    test('ignora otras apps y textos sin dígitos de tarjeta', () {
      expect(DetectorTarjetas.detectar('com.whatsapp', 'Ana', 'Mi Visa ••1234'), isNull);
      expect(DetectorTarjetas.detectar(_google, 'Google Wallet', 'Añade una tarjeta para pagar'), isNull);
      expect(DetectorTarjetas.detectar(_google, 'Mercadona', 'Total 1234 €'), isNull);
    });
  });

  group('Tarjetas detectadas', () {
    test('se proponen una vez; aceptar la guarda y descartar no la vuelve a proponer', () async {
      await ServicioNotificaciones.procesar(_google, 'Mercadona', '12,50 € con Visa ••1234');
      await ServicioNotificaciones.procesar(_google, 'Lidl', '8,00 € con Visa ••1234'); // repetida
      await ServicioNotificaciones.procesar(_samsung, 'Zara', 'Mastercard ••9876');
      await ServicioNotificaciones.procesar('com.whatsapp', 'Ana', 'Visa ••0000'); // no es un wallet
      expect(ServicioNotificaciones.detectadas.value, ['Visa ••1234', 'Mastercard ••9876']);

      await ServicioNotificaciones.aceptar('Visa ••1234');
      await ServicioNotificaciones.descartar('Mastercard ••9876');
      expect(ServicioNotificaciones.detectadas.value, isEmpty);
      expect(await ServicioTarjetas.cargar(), ['Visa ••1234']);

      // Ni la aceptada ni la descartada vuelven a aparecer
      await ServicioNotificaciones.procesar(_google, 'Bar', 'Visa ••1234');
      await ServicioNotificaciones.procesar(_samsung, 'Bar', 'Mastercard ••9876');
      expect(ServicioNotificaciones.detectadas.value, isEmpty);
    });

    test('los pagos recogidos más tarde conservan la hora de la notificación', () async {
      final llegada = DateTime(2024, 5, 10, 9, 30);
      await ServicioNotificaciones.procesar('com.paypal.android.p2pmobile', 'PayPal', 'Has pagado 10,00 € EUR a Amazon', fecha: llegada);
      final pago = ServicioPagosDetectados.pendientes.value.single;
      expect((pago.fecha, pago.comercio, pago.importe), (llegada, 'Amazon', 10.0));
    });

    test('se escuchan wallets, bancos del catálogo y apps de pago', () {
      expect(ServicioNotificaciones.paquetes, containsAll([_google, 'com.bbva.bbvacontigo', 'com.paypal.android.p2pmobile']));
      expect(ServicioNotificaciones.paquetes, isNot(contains('com.whatsapp')));
    });
  });

  group('Tarjeta', () {
    test('las tarjetas guardadas como texto se leen y se reconoce red y últimos 4', () async {
      SharedPreferences.setMockInitialValues({'tarjetas': '["Visa ••1234","Revolut"]'});
      final tarjetas = await ServicioTarjetas.cargarTarjetas();
      expect(tarjetas.map((t) => t.nombre), ['Visa ••1234', 'Revolut']);
      expect(tarjetas[0].red, 'Visa');
      expect(tarjetas[0].ultimos4, '1234');
      expect(tarjetas[1].red, isNull);

      // Al añadir otra, las antiguas se conservan
      expect(await ServicioTarjetas.anadirTarjeta(const Tarjeta(nombre: 'Amex ••0005', red: 'Amex', ultimos4: '0005')), isTrue);
      expect(await ServicioTarjetas.cargar(), ['Visa ••1234', 'Revolut', 'Amex ••0005']);

      await ServicioTarjetas.eliminar('revolut');
      expect(await ServicioTarjetas.cargar(), ['Visa ••1234', 'Amex ••0005']);
    });
  });

  group('Alta rápida', () {
    Future<void> abrir(WidgetTester tester, void Function(String?) alCerrar) async {
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
              onPressed: () async => alCerrar(await mostrarDialogoNuevaTarjeta(context)),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('los bancos de mis cuentas salen como chips; crédito y débito se asocia a la cuenta', (tester) async {
      final corriente = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA', tipo: TipoCuenta.corriente, bancoId: 'bbva');
      String? resultado;
      await abrir(tester, (r) => resultado = r);

      await tester.tap(find.widgetWithText(ChoiceChip, 'BBVA'));
      await tester.tap(find.text('Mastercard'));
      await tester.tap(find.text('Crédito'));
      await tester.enterText(find.widgetWithText(TextField, 'Últimos 4 dígitos (opcional)'), '9876');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir'));
      await tester.pumpAndSettle();
      expect(resultado, 'Mastercard BBVA crédito ••9876');
      expect((await ServicioTarjetas.cargarTarjetas()).single.cuentaId, isNull); // crédito: sin cuenta

      await abrir(tester, (r) => resultado = r);
      await tester.tap(find.widgetWithText(ChoiceChip, 'BBVA'));
      await tester.enterText(find.widgetWithText(TextField, 'Últimos 4 dígitos (opcional)'), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir'));
      await tester.pumpAndSettle();
      expect(resultado, 'Visa BBVA ••1234');
      expect((await ServicioTarjetas.cargarTarjetas()).last.cuentaId, corriente.id);
    });

    testWidgets('una tarjeta repetida muestra el aviso y no cierra', (tester) async {
      await ServicioTarjetas.anadir('Visa ING ••1111');
      String? resultado = 'sin tocar';
      await abrir(tester, (r) => resultado = r);

      await tester.enterText(find.widgetWithText(TextField, 'Banco'), 'ING');
      await tester.enterText(find.widgetWithText(TextField, 'Últimos 4 dígitos (opcional)'), '1111');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir'));
      await tester.pumpAndSettle();
      expect(find.text('Ya tienes esta tarjeta'), findsOneWidget);
      expect(resultado, 'sin tocar');
    });
  });

  testWidgets('el panel muestra alta manual y, fuera de Android, que la importación no está disponible', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.idiomasSoportados,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const PantallaTarjetas(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Importar tarjetas'), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing, reason: 'La lectura de notificaciones ya está terminada');
    expect(find.text('Disponible solo en Android.'), findsOneWidget);
    expect(find.text('Añadir tarjeta'), findsOneWidget);
  });

  testWidgets('los botones de solo icono tienen texto para lectores de pantalla', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.idiomasSoportados,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const PantallaTarjetas(),
    ));
    await tester.pumpAndSettle();

    for (final boton in tester.widgetList<IconButton>(find.byType(IconButton))) {
      expect(boton.tooltip, isNotNull, reason: 'IconButton sin tooltip');
    }
  });

  test('textos nuevos de mostrar u ocultar clave en todos los idiomas', () async {
    for (final idioma in AppLocalizations.idiomasSoportados) {
      final l10n = await AppLocalizations.delegate.load(idioma);
      expect(l10n.mostrarClave, isNot('mostrarClave'), reason: idioma.languageCode);
      expect(l10n.ocultarClave, isNot('ocultarClave'), reason: idioma.languageCode);
    }
  });
}
