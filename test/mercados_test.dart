import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_mercados.dart';
import 'package:presupuesto_familiar/servicios/api_bolsa.dart';
import 'package:presupuesto_familiar/servicios/config_mercados.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigMercados.cargar();
  });

  group('ConfigMercados', () {
    test('por defecto la conexión está desactivada y sin clave', () {
      expect(ConfigMercados.activa, isFalse);
      expect(ConfigMercados.tieneClave, isFalse);
      expect(ConfigMercados.conectada, isFalse);
    });

    test('activar sin clave no conecta: hace falta la clave del usuario', () async {
      await ConfigMercados.cambiarActiva(true);
      expect(ConfigMercados.conectada, isFalse);
      expect(await ApiBolsa.probarConexion(), isFalse);

      await ConfigMercados.guardarClave('  mi-clave-123 ');
      expect(ConfigMercados.clave, 'mi-clave-123');
      expect(ConfigMercados.conectada, isTrue);

      await ConfigMercados.cargar(); // se conserva al reabrir la app
      expect(ConfigMercados.clave, 'mi-clave-123');
      expect(ConfigMercados.activa, isTrue);
    });

    test('con la conexión desactivada no se hace ninguna llamada', () async {
      await ConfigMercados.guardarClave('mi-clave');
      await ConfigMercados.cambiarActiva(false);
      final inicio = DateTime.now();
      expect(await ApiBolsa.obtenerPrecioActual('AAPL.US'), isNull);
      expect(await ApiBolsa.buscarTickerPorIsin('US0378331005'), isNull);
      // Sin red ni reintentos (cada reintento esperaría 2 segundos)
      expect(DateTime.now().difference(inicio).inMilliseconds, lessThan(500));
    });
  });

  testWidgets('pantalla: desactivada por defecto; al activar se pide la clave y se guarda', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.idiomasSoportados,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const PantallaMercados(),
    ));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(ConfigMercados.activa, isTrue);
    expect(find.text('Sin clave: introduce la tuya para conectar'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'clave-propia');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(ConfigMercados.clave, 'clave-propia');
    expect(find.text('Usando tu clave'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('conexionMercados'), isTrue);
  });
}
