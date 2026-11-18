import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_principal.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_onboarding.dart';
import 'package:presupuesto_familiar/servicios/config_mercados.dart';
import 'package:presupuesto_familiar/servicios/open_banking/config_open_banking.dart';
import 'package:presupuesto_familiar/servicios/servicio_notificaciones.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';
import 'package:presupuesto_familiar/utilidades/tema.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale(AppLocalizations.idiomaPorDefecto));
final ValueNotifier<Moneda> monedaNotifier = ValueNotifier(Moneda.porDefecto);
final ValueNotifier<String> acentoNotifier = ValueNotifier(AppStrings.acentoPorDefecto);

// Guarda el modo claro/oscuro y lo aplica al instante
Future<void> cambiarModoOscuro(bool oscuro) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(DBKeys.modoOscuro, oscuro);
  themeNotifier.value = oscuro ? ThemeMode.dark : ThemeMode.light;
}

// Guarda el color de acento y repinta toda la app
Future<void> cambiarAcento(String clave) async {
  final valida = Tema.acentoValido(clave);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(DBKeys.colorAcento, valida);
  acentoNotifier.value = valida;
}

// Guarda el idioma elegido y lo aplica al instante en toda la app
Future<void> cambiarIdioma(String codigo) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(DBKeys.idioma, codigo);
  localeNotifier.value = Locale(codigo);
}

// Guarda la moneda principal y actualiza todos los importes visibles
Future<void> cambiarMoneda(String codigo) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(DBKeys.moneda, codigo);
  monedaNotifier.value = Moneda.desdeCodigo(codigo);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final esOscuro = prefs.getBool(DBKeys.modoOscuro) ?? false;
  // Si no existe la variable, asume que es la primera vez (true)
  final esPrimeraVez = prefs.getBool(DBKeys.esPrimeraVez) ?? true;

  themeNotifier.value = esOscuro ? ThemeMode.dark : ThemeMode.light;
  localeNotifier.value = Locale(_idiomaInicial(prefs.getString(DBKeys.idioma)));
  monedaNotifier.value = Moneda.desdeCodigo(prefs.getString(DBKeys.moneda));
  acentoNotifier.value = Tema.acentoValido(prefs.getString(DBKeys.colorAcento));
  await ConfigMercados.cargar();
  await ConfigOpenBanking.cargar();

  runApp(MyApp(esPrimeraVez: esPrimeraVez));

  // Lectura de notificaciones (en desarrollo): solo si el usuario la activó y dio permiso
  ServicioNotificaciones.iniciarSiActivado();
}

// Idioma guardado; si no hay (o es un valor antiguo), el del dispositivo si está soportado
String _idiomaInicial(String? guardado) {
  if (AppLocalizations.esSoportado(guardado)) return guardado!;
  final idiomaDispositivo = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  if (AppLocalizations.esSoportado(idiomaDispositivo)) return idiomaDispositivo;
  return AppLocalizations.idiomaPorDefecto;
}

class MyApp extends StatelessWidget {
  final bool esPrimeraVez;

  const MyApp({super.key, required this.esPrimeraVez});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeNotifier, localeNotifier, acentoNotifier]),
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: Tema.construir(acento: acentoNotifier.value, brillo: Brightness.light),
          darkTheme: Tema.construir(acento: acentoNotifier.value, brillo: Brightness.dark),
          themeMode: themeNotifier.value,
          locale: localeNotifier.value,
          supportedLocales: AppLocalizations.idiomasSoportados,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // La moneda llega a todas las pantallas (y diálogos) a través de MonedaScope
          builder: (context, child) => MonedaScope(notifier: monedaNotifier, child: child!),
          // Interceptor de inicio
          home: esPrimeraVez ? const PantallaOnboarding() : const PantallaPrincipal(),
        );
      },
    );
  }
}