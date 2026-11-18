import 'package:presupuesto_familiar/constants/db_keys.dart';

class Transaccion {
  final int? id;
  final int montoEnCentimos;
  final String concepto;
  final DateTime fecha;
  final String categoria;
  final bool esIngreso;
  final String tarroDestino;
  final String? metodoPago; // AppStrings.metodoEfectivo / metodoTarjeta; null en ingresos y automáticos
  final String? tarjeta; // Nombre de la tarjeta cuando metodoPago es tarjeta
  final String? cuentaAhorro; // id de la cuenta de ahorro (solo en movimientos de Ahorro)
  final String? tiquet; // Nombre del archivo de la foto del tiquet (ServicioTiquets)

  Transaccion({
    this.id,
    required this.montoEnCentimos,
    required this.concepto,
    required this.fecha,
    required this.categoria,
    required this.esIngreso,
    required this.tarroDestino,
    this.metodoPago,
    this.tarjeta,
    this.cuentaAhorro,
    this.tiquet,
  });

  Map<String, dynamic> toMap() {
    return {
      DBKeys.columnId: id,
      DBKeys.columnMonto: montoEnCentimos,
      DBKeys.columnConcepto: concepto,
      DBKeys.columnFecha: fecha.toIso8601String(),
      DBKeys.columnCategoria: categoria,
      DBKeys.columnEsIngreso: esIngreso ? 1 : 0,
      DBKeys.columnTarro: tarroDestino,
      DBKeys.columnMetodoPago: metodoPago,
      DBKeys.columnTarjeta: tarjeta,
      DBKeys.columnCuentaAhorro: cuentaAhorro,
      DBKeys.columnTiquet: tiquet,
    };
  }

  factory Transaccion.fromMap(Map<String, dynamic> mapa) {
    return Transaccion(
      id: mapa[DBKeys.columnId],
      montoEnCentimos: mapa[DBKeys.columnMonto],
      concepto: mapa[DBKeys.columnConcepto],
      fecha: DateTime.parse(mapa[DBKeys.columnFecha]),
      categoria: mapa[DBKeys.columnCategoria],
      esIngreso: mapa[DBKeys.columnEsIngreso] == 1,
      tarroDestino: mapa[DBKeys.columnTarro],
      metodoPago: mapa[DBKeys.columnMetodoPago],
      tarjeta: mapa[DBKeys.columnTarjeta],
      cuentaAhorro: mapa[DBKeys.columnCuentaAhorro],
      tiquet: mapa[DBKeys.columnTiquet],
    );
  }
}