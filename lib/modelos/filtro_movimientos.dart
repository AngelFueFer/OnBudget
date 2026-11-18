import 'package:flutter/material.dart' show DateTimeRange;
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';

// Filtro de la lista de movimientos: categorías, rango de importe y rango de fechas.
// Un criterio vacío (null o conjunto vacío) no filtra.
class FiltroMovimientos {
  final Set<String> categorias;
  final double? importeMinimo;
  final double? importeMaximo;
  final DateTimeRange? fechas;

  const FiltroMovimientos({
    this.categorias = const {},
    this.importeMinimo,
    this.importeMaximo,
    this.fechas,
  });

  static const FiltroMovimientos vacio = FiltroMovimientos();

  bool get filtraCategorias => categorias.isNotEmpty;
  bool get filtraImporte => importeMinimo != null || importeMaximo != null;
  bool get filtraFechas => fechas != null;

  // Número de criterios activos (para el indicador del botón de filtro)
  int get criteriosActivos => (filtraCategorias ? 1 : 0) + (filtraImporte ? 1 : 0) + (filtraFechas ? 1 : 0);
  bool get activo => criteriosActivos > 0;

  // Categoría e importe; sirve también para las inversiones (categoría = ticker, importe = valor de la operación)
  bool cumpleCategoriaEImporte(String categoria, double importe) {
    if (filtraCategorias && !categorias.contains(categoria)) return false;
    if (importeMinimo != null && importe < importeMinimo!) return false;
    if (importeMaximo != null && importe > importeMaximo!) return false;
    return true;
  }

  bool cumple(Transaccion t) {
    if (!cumpleCategoriaEImporte(t.categoria, t.montoEnCentimos / AppNumbers.centimosEnEuro)) return false;

    if (fechas != null) {
      // Días completos: desde las 00:00 del inicio hasta las 23:59:59 del final
      final inicio = DateTime(fechas!.start.year, fechas!.start.month, fechas!.start.day);
      final finExclusivo = DateTime(fechas!.end.year, fechas!.end.month, fechas!.end.day + 1);
      if (t.fecha.isBefore(inicio) || !t.fecha.isBefore(finExclusivo)) return false;
    }
    return true;
  }

  FiltroMovimientos sinCategorias() =>
      FiltroMovimientos(importeMinimo: importeMinimo, importeMaximo: importeMaximo, fechas: fechas);

  FiltroMovimientos sinImporte() => FiltroMovimientos(categorias: categorias, fechas: fechas);

  FiltroMovimientos sinFechas() =>
      FiltroMovimientos(categorias: categorias, importeMinimo: importeMinimo, importeMaximo: importeMaximo);
}
