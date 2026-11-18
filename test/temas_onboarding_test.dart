import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/main.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_temas.dart';
import 'package:presupuesto_familiar/utilidades/tema.dart';
import 'package:presupuesto_familiar/utilidades/url_servidor.dart';

void main() {
  group('Color de acento', () {
    test('por defecto es el azul del logo y una clave desconocida vuelve al defecto', () {
      expect(AppStrings.acentoPorDefecto, AppStrings.acentoAzul);
      expect(Tema.acentoValido(null), AppStrings.acentoAzul);
      expect(Tema.acentoValido('fucsia'), AppStrings.acentoAzul);
      expect(Tema.acentoValido(AppStrings.acentoBlanco), AppStrings.acentoBlanco);
    });

    test('sin elección guardada, el tema claro y el oscuro usan el azul del logo', () {
      for (final brillo in Brightness.values) {
        final primario = Tema.construir(acento: Tema.acentoValido(null), brillo: brillo).colorScheme.primary;
        final tono = HSVColor.fromColor(primario).hue;
        expect(tono, inInclusiveRange(185, 215), reason: '$brillo: $primario'); // Azul del logo ≈ 197º
      }
    });

    test('el blanco es blanco en modo oscuro y negro en modo claro', () {
      final oscuro = Tema.construir(acento: AppStrings.acentoBlanco, brillo: Brightness.dark).colorScheme;
      final claro = Tema.construir(acento: AppStrings.acentoBlanco, brillo: Brightness.light).colorScheme;
      expect(oscuro.primary, const Color(0xFFFFFFFF));
      expect(claro.primary, const Color(0xFF000000));
      // El texto sobre el acento contrasta en ambos modos
      expect(ThemeData.estimateBrightnessForColor(oscuro.onPrimary), Brightness.dark);
      expect(ThemeData.estimateBrightnessForColor(claro.onPrimary), Brightness.light);
    });

    test('cada acento tiene nombre en todos los idiomas', () {
      for (final idioma in AppLocalizations.idiomasSoportados) {
        final l10n = AppLocalizations(idioma.languageCode);
        for (final clave in AppColors.coloresAcento.keys) {
          expect(l10n.nombreAcento(clave), isNot('acento.$clave'), reason: '${idioma.languageCode}: $clave');
        }
      }
    });

    test('cambiarAcento guarda la clave (sin traducir) y avisa a la app', () async {
      SharedPreferences.setMockInitialValues({});
      await cambiarAcento(AppStrings.acentoMorado);
      expect(acentoNotifier.value, AppStrings.acentoMorado);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DBKeys.colorAcento), 'morado');
    });

    testWidgets('Temas reúne el modo oscuro y el color de acento', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      localeNotifier.value = const Locale('es');
      themeNotifier.value = ThemeMode.light;
      acentoNotifier.value = AppStrings.acentoBlanco;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.idiomasSoportados,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const PantallaTemas(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modo Oscuro'));
      await tester.pumpAndSettle();
      expect(themeNotifier.value, ThemeMode.dark);

      await tester.tap(find.text('Azul'));
      await tester.pumpAndSettle();
      expect(acentoNotifier.value, AppStrings.acentoAzul);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(DBKeys.modoOscuro), isTrue);
      expect(prefs.getString(DBKeys.colorAcento), AppStrings.acentoAzul);
    });
  });

  group('Dirección del servidor propio', () {
    test('acepta direcciones válidas y las limpia', () {
      expect(UrlServidor.normalizar('presupuesto.midominio.com'), 'https://presupuesto.midominio.com');
      expect(UrlServidor.normalizar('  https://mi.servidor.es/ '), 'https://mi.servidor.es');
      expect(UrlServidor.normalizar('http://192.168.1.20:8080'), 'http://192.168.1.20:8080');
      expect(UrlServidor.normalizar('http://localhost:8080'), 'http://localhost:8080');
    });

    test('rechaza texto vacío, palabras sueltas y otros esquemas', () {
      expect(UrlServidor.normalizar(''), isNull);
      expect(UrlServidor.normalizar('servidor'), isNull);
      expect(UrlServidor.normalizar('ftp://mi.servidor.es'), isNull);
      expect(UrlServidor.normalizar('mi servidor.es'), isNull);
    });
  });

  group('Onboarding', () {
    Future<void> abrir(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      localeNotifier.value = const Locale('es');
      await tester.pumpWidget(const MyApp(esPrimeraVez: true));
      await tester.pumpAndSettle();
    }

    Future<void> siguiente(WidgetTester tester) async {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
    }

    testWidgets('orden: idioma, servidor o local, finanzas, gastos fijos y tarjetas al final', (WidgetTester tester) async {
      await abrir(tester);
      expect(find.text('Apariencia e Idioma'), findsOneWidget);

      await siguiente(tester);
      expect(find.text('¿Dónde guardamos tus datos?'), findsOneWidget);
      expect(find.text('Solo en este dispositivo'), findsOneWidget);

      await siguiente(tester);
      expect(find.text('Tus datos financieros'), findsOneWidget);

      await siguiente(tester);
      expect(find.text('Gastos Fijos'), findsOneWidget);

      await siguiente(tester);
      expect(find.text('Importar tarjetas'), findsWidgets);
      // La lectura de notificaciones sigue en este paso; la conexión con el banco no
      expect(find.text('Mis tarjetas'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);
    });

    testWidgets('con servidor propio no avanza sin una dirección válida', (WidgetTester tester) async {
      await abrir(tester);
      await siguiente(tester);
      await tester.tap(find.text('Servidor propio'));
      await tester.pumpAndSettle();

      await siguiente(tester);
      expect(find.text('¿Dónde guardamos tus datos?'), findsOneWidget);
      expect(find.text('Escribe una dirección válida (ej. https://midominio.com)'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Dirección del servidor'), 'presupuesto.midominio.com');
      await siguiente(tester);
      expect(find.text('Tus datos financieros'), findsOneWidget);
    });
  });
}
