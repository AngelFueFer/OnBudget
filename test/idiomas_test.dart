import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/l10n/traducciones/es.dart';
import 'package:presupuesto_familiar/main.dart';

// Marcadores como {mes} o {n} que el código sustituye al formatear
Set<String> _marcadores(String texto) =>
    RegExp(r'\{(\w+)\}').allMatches(texto).map((m) => m.group(1)!).toSet();

void main() {
  final tablas = AppLocalizations.tablasTraduccion;

  group('Idiomas', () {
    test('los idiomas del selector coinciden con los soportados', () {
      final soportados = AppLocalizations.idiomasSoportados.map((l) => l.languageCode).toSet();
      expect(AppStrings.idiomasDisponibles.keys.toSet(), soportados);
      expect(soportados, containsAll(['es', 'en', 'fr', 'de', 'pt', 'it', 'nl', 'pl', 'ca', 'tr', 'zh', 'ja']));
    });

    test('cada idioma tiene exactamente las mismas claves que el español', () {
      for (final entrada in tablas.entries) {
        final claves = entrada.value.keys.toSet();
        expect(es.keys.toSet().difference(claves), isEmpty, reason: '${entrada.key}: faltan claves');
        expect(claves.difference(es.keys.toSet()), isEmpty, reason: '${entrada.key}: sobran claves');
      }
    });

    test('ningún texto está vacío y los marcadores son los mismos que en español', () {
      for (final entrada in tablas.entries) {
        entrada.value.forEach((clave, texto) {
          expect(texto.trim(), isNotEmpty, reason: '${entrada.key}: $clave vacío');
          expect(_marcadores(texto), _marcadores(es[clave]!), reason: '${entrada.key}: $clave');
        });
      }
    });

    test('Material y Cupertino traen sus propios textos para todos los idiomas', () {
      for (final locale in AppLocalizations.idiomasSoportados) {
        expect(GlobalMaterialLocalizations.delegate.isSupported(locale), isTrue, reason: locale.languageCode);
        expect(GlobalCupertinoLocalizations.delegate.isSupported(locale), isTrue, reason: locale.languageCode);
      }
    });

    test('las categorías creadas por el usuario no se traducen en ningún idioma', () {
      for (final codigo in tablas.keys) {
        final l10n = AppLocalizations(codigo);
        expect(l10n.nombreCategoria('Mascotas'), 'Mascotas');
        expect(l10n.nombreCategoria('Supermercado'), isNot('cat.Supermercado'));
      }
    });

    test('el remanente guardado en español se muestra con el mes del idioma', () {
      final concepto = AppStrings.conceptoRemanente('2026-09');
      expect(AppLocalizations('it').concepto(concepto), 'Avanzo di settembre 2026');
      expect(AppLocalizations('ja').concepto(concepto), '2026年9月の繰越');
      expect(AppLocalizations('pt').concepto(concepto), 'Sobra de setembro de 2026');
    });

    test('cambiarIdioma guarda el código (sin traducir) y avisa a la app', () async {
      SharedPreferences.setMockInitialValues({});
      await cambiarIdioma('pl');
      expect(localeNotifier.value, const Locale('pl'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DBKeys.idioma), 'pl');
      await cambiarIdioma(AppLocalizations.idiomaPorDefecto);
    });
  });
}
