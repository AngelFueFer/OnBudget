// Genera capturas de la app con datos de ejemplo para la web y la ficha de Google Play.
// Uso: flutter test tool/capturas/capturas_test.dart  (deja los PNG en sitio_web/capturas/)
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/main.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';

const _carpeta = 'sitio_web/capturas';

Future<void> _cargarFuentes() async {
  final base = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> cargar(String familia, List<String> archivos) async {
    final cargador = FontLoader(familia);
    for (final a in archivos) {
      final bytes = File('$base/$a').readAsBytesSync();
      cargador.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await cargador.load();
  }

  await cargar('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']);
  await cargar('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _sembrar() async {
  final db = DBHelper();
  final hoy = DateTime.now();
  DateTime dia(int d) => DateTime(hoy.year, hoy.month, d.clamp(1, hoy.day));
  final gastos = [
    (4235, 'Mercadona', 'Supermercado', 2),
    (1890, 'Gasolinera', 'Transporte', 3),
    (3260, 'Cena con amigos', 'Restaurantes', 5),
    (5480, 'Factura de la luz', 'Luz', 6),
    (2799, 'Lidl', 'Supermercado', 8),
    (1500, 'Cine', 'Ocio', 9),
    (3995, 'Zapatillas', 'Ropa', 10),
    (2150, 'Carrefour', 'Supermercado', 12),
    (1200, 'Abono transporte', 'Transporte', 12),
    (2480, 'Agua', 'Agua', 14),
    (850, 'Café y churros', 'Restaurantes', 15),
    (6420, 'Ikea', 'Hogar', 16),
  ];
  for (final g in gastos) {
    await db.insertarTransaccion(Transaccion(
      montoEnCentimos: g.$1,
      concepto: g.$2,
      fecha: dia(g.$4),
      categoria: g.$3,
      esIngreso: false,
      tarroDestino: AppStrings.cuentaMensual,
      metodoPago: AppStrings.metodoTarjeta,
    ));
  }
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  // La base de datos va por FFI (asíncrono real): se alternan esperas reales y frames
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 300));
  }
  final limite = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final imagen = await tester.runAsync(() => limite.toImage(pixelRatio: tester.view.devicePixelRatio));
  final bytes = await tester.runAsync(() => imagen!.toByteData(format: ui.ImageByteFormat.png));
  Directory(_carpeta).createSync(recursive: true);
  File('$_carpeta/$nombre.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    DBHelper.fabricaBaseDatos = databaseFactoryFfi;
    DBHelper.rutaBaseDatos = inMemoryDatabasePath;
    await _cargarFuentes();
  });

  // Prepara un móvil de 1080×2160 (proporción 2:1, la máxima que admite Google Play) con datos de ejemplo (nunca datos reales)
  Future<void> preparar(WidgetTester tester, {bool oscuro = false, bool primeraVez = false}) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      DBKeys.esPrimeraVez: primeraVez,
      DBKeys.nominaMensual: 2400.0,
      DBKeys.gastoMensual: 1500.0,
      DBKeys.diaCobro: 1,
      DBKeys.modoOscuro: oscuro,
    });
    themeNotifier.value = oscuro ? ThemeMode.dark : ThemeMode.light;
    await tester.runAsync(() async {
      await DBHelper().cerrar();
      await _sembrar();
    });
    await tester.pumpWidget(MyApp(esPrimeraVez: primeraVez));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
  }

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  // Cada pantalla en claro y en oscuro: la web muestra la que corresponde al tema del visitante
  final pantallas = <String, Future<void> Function(WidgetTester)>{
    'principal': (tester) async {},
    'nuevo-gasto': (tester) async {
      await tester.tap(find.byIcon(Icons.remove));
    },
    'temas': (tester) async {
      await tester.tap(find.byIcon(Icons.settings).first);
      await esperar(tester);
      await tester.tap(find.text('Temas'));
    },
    'configuracion': (tester) async {
      await tester.tap(find.byIcon(Icons.settings).first);
    },
    'bienvenida': (tester) async {},
  };

  for (final pantalla in pantallas.entries) {
    for (final oscuro in [false, true]) {
      final nombre = '${pantalla.key}-${oscuro ? 'oscuro' : 'claro'}';
      testWidgets(nombre, (tester) async {
        await preparar(tester, oscuro: oscuro, primeraVez: pantalla.key == 'bienvenida');
        await esperar(tester);
        await pantalla.value(tester);
        await _capturar(tester, nombre);
      });
    }
  }
}
