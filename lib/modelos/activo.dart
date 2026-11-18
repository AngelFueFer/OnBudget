import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';

class ActivoFinanciero {
  final int? id;
  final String ticker; // Ej: SAN.MC, AAPL.US. Si un ISIN no se pudo resolver, contiene el ISIN
  final double cantidad; // Número de acciones o participaciones
  final double precioCompra;
  final String? tipo; // AppStrings.tiposInversion; null en activos antiguos (= acción)
  final String? nombre; // Nombre que le da el usuario (opcional)
  final String? isin; // Si se dio de alta por ISIN

  ActivoFinanciero({
    this.id,
    required this.ticker,
    required this.cantidad,
    required this.precioCompra,
    this.tipo,
    this.nombre,
    this.isin,
  });

  String get tipoEfectivo => tipo ?? AppStrings.tipoAccion;

  // Lo que se muestra en la lista: el nombre propio o, si no hay, el ticker
  String get nombreVisible => (nombre != null && nombre!.trim().isNotEmpty) ? nombre!.trim() : ticker;

  Map<String, dynamic> toMap() {
    return {
      DBKeys.columnId: id,
      DBKeys.columnTicker: ticker.toUpperCase(),
      DBKeys.columnCantidad: cantidad,
      DBKeys.columnPrecioCompra: precioCompra,
      DBKeys.columnTipo: tipo,
      DBKeys.columnNombre: nombre,
      DBKeys.columnIsin: isin,
    };
  }

  factory ActivoFinanciero.fromMap(Map<String, dynamic> mapa) {
    return ActivoFinanciero(
      id: mapa[DBKeys.columnId],
      ticker: mapa[DBKeys.columnTicker],
      cantidad: mapa[DBKeys.columnCantidad],
      precioCompra: mapa[DBKeys.columnPrecioCompra],
      tipo: mapa[DBKeys.columnTipo],
      nombre: mapa[DBKeys.columnNombre],
      isin: mapa[DBKeys.columnIsin],
    );
  }

  ActivoFinanciero copiarConTicker(String nuevoTicker) => ActivoFinanciero(
        id: id,
        ticker: nuevoTicker,
        cantidad: cantidad,
        precioCompra: precioCompra,
        tipo: tipo,
        nombre: nombre,
        isin: isin,
      );
}
