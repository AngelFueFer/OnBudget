import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';

class AppColors {
  // Colores de marca (los mismos del logo: tool/generar_logo.py)
  static const Color primary = Color(0xFF14A889);
  static const Color marcaClaro = Color(0xFF2BD18E);
  static const Color marcaOscuro = Color(0xFF0E8C7F);
  // En la interfaz usa Theme.of(context).colorScheme.primary: sigue el color de acento elegido

  // Colores de acento elegibles en Configuración > Temas (clave guardada -> color semilla)
  static const Color acentoBlanco = Colors.white; // Monocromo: blanco en oscuro, negro en claro
  static const Color acentoAzul = Color(0xFF147AA3); // Azul del logo (tool/generar_logo.py)
  static const Map<String, Color> coloresAcento = {
    AppStrings.acentoAzul: acentoAzul,
    AppStrings.acentoBlanco: acentoBlanco,
    AppStrings.acentoVerde: primary,
    AppStrings.acentoMorado: Colors.deepPurple,
    AppStrings.acentoNaranja: Colors.deepOrange,
    AppStrings.acentoRosa: Colors.pink,
  };

  // Colores por categoría de gasto
  static const Map<String, Color> categoryColors = {
    'Comida': Colors.orange,
    'Hogar': Colors.teal,
    'Transporte': Colors.blue,
    'Ocio': Colors.purple,
    'Salario': Colors.green,
    'General': Colors.grey,
    'Supermercado': Colors.orange,
    'Restaurantes': Colors.deepOrange,
    'Ropa': Colors.pink,
    'Teléfono': Colors.cyan,
    'Luz': Colors.amber,
    'Agua': Colors.lightBlue,
  };

  // Colores de saldo y cuentas
  static const Color saldoPositivo = Colors.green;
  static const Color saldoNegativo = Colors.red;

  // Colores de estado
  static const Color exito = Colors.green;
  static const Color error = Colors.red;
  static const Color advertencia = Colors.orange;
  static const Color info = Colors.blue;

  // Obtener color para una categoría
  static Color obtenerColorCategoria(String categoria) {
    return categoryColors[categoria] ?? Colors.grey;
  }
}
