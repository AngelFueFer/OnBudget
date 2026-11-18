import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/l10n/traducciones/es.dart';
import 'package:presupuesto_familiar/l10n/traducciones/en.dart';
import 'package:presupuesto_familiar/l10n/traducciones/fr.dart';
import 'package:presupuesto_familiar/l10n/traducciones/de.dart';
import 'package:presupuesto_familiar/main.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

void main() {
  group('Traducciones', () {
    final idiomas = {'en': en, 'fr': fr, 'de': de};

    for (final idioma in idiomas.entries) {
      test('${idioma.key} tiene exactamente las mismas claves que es', () {
        expect(idioma.value.keys.toSet().difference(es.keys.toSet()), isEmpty, reason: 'Claves sobrantes');
        expect(es.keys.toSet().difference(idioma.value.keys.toSet()), isEmpty, reason: 'Claves que faltan');
      });

      test('${idioma.key} conserva los marcadores {..} de cada texto', () {
        final marcador = RegExp(r'\{\w+\}');
        for (final clave in es.keys) {
          final esperados = marcador.allMatches(es[clave]!).map((m) => m.group(0)).toSet();
          final reales = marcador.allMatches(idioma.value[clave]!).map((m) => m.group(0)).toSet();
          expect(reales, esperados, reason: 'Clave "$clave"');
        }
      });
    }

    test('todas las categorías por defecto tienen traducción', () {
      final categorias = {
        ...AppStrings.categoriasDefecto,
        ...AppStrings.categoriasGastosFijos,
        ...AppStrings.categoriasConIconoDefecto.map((c) => c['nombre']!),
      };
      for (final categoria in categorias) {
        expect(es.containsKey('cat.$categoria'), isTrue, reason: categoria);
      }
    });

    test('los valores guardados se traducen solo al mostrarse', () {
      final l10n = AppLocalizations('fr');
      expect(l10n.nombreCategoria('Supermercado'), 'Supermarché');
      expect(l10n.nombreCategoria('Mi categoría'), 'Mi categoría');
      expect(l10n.nombreCuenta(AppStrings.ahorro), 'Épargne');
      expect(l10n.concepto(AppStrings.nominaParteAhorro), 'Salaire (part Épargne)');
      expect(l10n.resumenPresupuesto('10 €', '20 €'), 'Budget : 10 € / 20 €');
    });

    test('el remanente se guarda con fecha y se muestra con el mes traducido', () {
      final concepto = AppStrings.conceptoRemanente('2026-09');
      expect(concepto, 'Remanente 2026-09');
      expect(AppLocalizations('es').concepto(concepto), 'Remanente de septiembre de 2026');
      expect(AppLocalizations('en').concepto(concepto), 'Carryover from September 2026');
      expect(AppLocalizations('fr').concepto(concepto), 'Report de septembre 2026');
      expect(AppLocalizations('es').concepto('Remanente de pan'), 'Remanente de pan');
      expect(AppLocalizations('es').concepto(AppStrings.conceptoDeficit('2026-09')), 'Déficit de septiembre de 2026');
      expect(AppLocalizations('en').concepto(AppStrings.conceptoDeficit('2026-09')), 'Deficit from September 2026');
    });
  });

  group('Moneda', () {
    test('formatea cada moneda con su símbolo y decimales', () {
      expect(Moneda.eur.formatear(12.5), '12.50 €');
      expect(Moneda.usd.formatear(-12.5), '-\$12.50');
      expect(Moneda.gbp.formatear(3, conSigno: true), '+£3.00');
      expect(Moneda.cny.formatear(8), 'CN¥8.00');
      expect(Moneda.jpy.formatear(1500.4), '¥1500');
    });

    test('un código desconocido o vacío usa el euro', () {
      expect(Moneda.desdeCodigo('JPY'), Moneda.jpy);
      expect(Moneda.desdeCodigo(null), Moneda.eur);
      expect(Moneda.desdeCodigo('XXX'), Moneda.eur);
    });

    testWidgets('cambiar la moneda actualiza los importes en pantalla', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      monedaNotifier.value = Moneda.eur;
      await tester.pumpWidget(MonedaScope(
        notifier: monedaNotifier,
        child: Builder(builder: (context) => Text(Moneda.of(context).formatear(10), textDirection: TextDirection.ltr)),
      ));
      expect(find.text('10.00 €'), findsOneWidget);

      await cambiarMoneda('USD');
      await tester.pump();
      expect(find.text('\$10.00'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('moneda'), 'USD');
    });
  });

  group('Tarjetas', () {
    test('se guardan por nombre y no se duplican', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ServicioTarjetas.anadir('Visa BBVA'), isTrue);
      expect(await ServicioTarjetas.anadir('  visa bbva '), isFalse);
      expect(await ServicioTarjetas.anadir('   '), isFalse);
      expect(await ServicioTarjetas.anadir('Revolut'), isTrue);
      expect(await ServicioTarjetas.cargar(), ['Visa BBVA', 'Revolut']);
    });
  });

  testWidgets('el cambio de idioma se aplica en vivo', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    localeNotifier.value = const Locale('es');

    await tester.pumpWidget(const MyApp(esPrimeraVez: true));
    await tester.pumpAndSettle();
    // Apariencia e idioma es el primer paso
    expect(find.text('Apariencia e Idioma'), findsOneWidget);

    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance and Language'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.ensureVisible(find.text('Français'));
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(find.text('Apparence et Langue'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('idioma'), 'fr');
  });
}
