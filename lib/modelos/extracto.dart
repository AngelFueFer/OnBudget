// Datos leídos de un extracto bancario (Norma 43 o CSV) antes de importarlos.

class MovimientoExtracto {
  final DateTime fecha;
  final String concepto;
  final double importe; // Negativo = cargo (gasto), positivo = abono (ingreso)

  const MovimientoExtracto({required this.fecha, required this.concepto, required this.importe});

  bool get esIngreso => importe > 0;
  int get centimos => (importe.abs() * 100).round();
}

class ExtractoCuenta {
  // CCC de la cuenta (solo Norma 43), para reconocer a qué cuenta del usuario pertenece
  final String? entidad;
  final String? oficina;
  final String? numeroCuenta;
  final double? saldoFinal;
  final DateTime? fechaSaldo;
  final List<MovimientoExtracto> movimientos;

  const ExtractoCuenta({
    this.entidad,
    this.oficina,
    this.numeroCuenta,
    this.saldoFinal,
    this.fechaSaldo,
    required this.movimientos,
  });
}

class FormatoExtractoNoValido implements Exception {
  final String motivo;
  const FormatoExtractoNoValido(this.motivo);

  @override
  String toString() => 'FormatoExtractoNoValido: $motivo';
}
