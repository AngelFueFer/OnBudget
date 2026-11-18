import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';

// Tema de la app a partir del color de acento guardado
class Tema {
  // Una clave desconocida (o vacía) usa el acento por defecto
  static String acentoValido(String? clave) =>
      AppColors.coloresAcento.containsKey(clave) ? clave! : AppStrings.acentoPorDefecto;

  static ThemeData construir({required String acento, required Brightness brillo}) {
    final clave = acentoValido(acento);
    final esMonocromo = clave == AppStrings.acentoBlanco;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.coloresAcento[clave]!,
        brightness: brillo,
        // El blanco no tiene tono: monocromo da blanco en modo oscuro y negro en claro (siempre legible)
        dynamicSchemeVariant: esMonocromo ? DynamicSchemeVariant.monochrome : DynamicSchemeVariant.tonalSpot,
      ),
      useMaterial3: true,
    );
  }
}
