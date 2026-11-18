import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/activo.dart';
import 'package:presupuesto_familiar/pantallas/formulario_inversion.dart';
import 'package:presupuesto_familiar/servicios/api_bolsa.dart';
import 'package:presupuesto_familiar/utilidades/isin.dart';

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
  group('Isin', () {
    test('reconoce ISIN reales con dígito de control correcto', () {
      expect(Isin.esValido('US0378331005'), isTrue); // Apple
      expect(Isin.esValido('ES0113900J37'), isTrue); // Banco Santander
      expect(Isin.esValido('IE00B4L5Y983'), isTrue); // iShares Core MSCI World
      expect(Isin.esValido(' es0113900j37 '), isTrue); // minúsculas y espacios
    });

    test('rechaza dígito de control erróneo y formatos que no son ISIN', () {
      expect(Isin.esValido('US0378331006'), isFalse);
      expect(Isin.pareceIsin('US0378331006'), isTrue); // tiene forma de ISIN, pero no es válido
      expect(Isin.pareceIsin('AAPL.US'), isFalse);
      expect(Isin.pareceIsin('BTC-USD.CC'), isFalse);
      expect(Isin.esValido('US037833100'), isFalse); // le falta un carácter
    });

    test('no se gastan llamadas a la API pidiendo el precio de un ISIN', () async {
      expect(await ApiBolsa.obtenerPrecioActual('ES0113900J37'), isNull);
    });
  });

  group('ActivoFinanciero', () {
    test('sin tipo es una acción y sin nombre se muestra el ticker', () {
      final antiguo = ActivoFinanciero(ticker: 'SAN.MC', cantidad: 10, precioCompra: 4);
      expect(antiguo.tipoEfectivo, AppStrings.tipoAccion);
      expect(antiguo.nombreVisible, 'SAN.MC');

      final etf = ActivoFinanciero(ticker: 'IWDA.AS', cantidad: 1, precioCompra: 90, tipo: AppStrings.tipoEtf, nombre: ' MSCI World ');
      expect(etf.tipoEfectivo, AppStrings.tipoEtf);
      expect(etf.nombreVisible, 'MSCI World');
    });
  });

  group('Formulario de inversión', () {
    testWidgets('muestra los seis tipos y preselecciona el del desplegable', (tester) async {
      await _abrir(tester, const FormularioInversion(tipoPredefinido: AppStrings.tipoCripto));
      for (final tipo in ['Materias primas', 'Acción ordinaria', 'ETF', 'Renta fija (bonos)', 'Derivado', 'Cripto']) {
        expect(find.widgetWithText(ChoiceChip, tipo), findsOneWidget);
      }
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cripto')).selected, isTrue);
      expect(find.text('Ticker o ISIN'), findsOneWidget);
      expect(find.text('Nombre (opcional)'), findsOneWidget);
    });

    testWidgets('un ISIN con el dígito de control mal muestra error y no guarda', (tester) async {
      await _abrir(tester, const FormularioInversion());
      await tester.enterText(find.widgetWithText(TextField, 'Ticker o ISIN'), 'US0378331006');
      await tester.enterText(find.widgetWithText(TextField, 'Cantidad de títulos'), '2');
      await tester.enterText(find.widgetWithText(TextField, 'Precio por título'), '150');
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('ISIN no válido: revisa los caracteres'), findsOneWidget);
      expect(find.byType(FormularioInversion), findsOneWidget); // sigue abierto
    });

    testWidgets('la compra rápida copia tipo, nombre e ISIN del activo', (tester) async {
      final base = ActivoFinanciero(
        ticker: 'SAN.MC',
        isin: 'ES0113900J37',
        nombre: 'Santander',
        tipo: AppStrings.tipoAccion,
        cantidad: 10,
        precioCompra: 4,
      );
      await _abrir(tester, FormularioInversion(activoBase: base, precioPredefinido: 4.5));
      expect(find.text('ES0113900J37'), findsOneWidget);
      expect(find.text('Santander'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Acción ordinaria')).selected, isTrue);
    });
  });
}
