import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';

// Vistas del Presupuesto Mensual (selector centrado de la barra superior)
enum VistaPresupuesto { efectivo, tarjeta, total }

// Reparto de la Cuenta Mensual entre efectivo y tarjeta.
//
// - Total: la cuenta completa (como siempre).
// - Efectivo: el límite de efectivo del mes menos lo pagado en efectivo este periodo.
// - Tarjeta: el total menos el efectivo que queda. Sin límite de efectivo es una réplica del total.
//
// Siempre se cumple Tarjeta + Efectivo = Total (si hay límite).
// Los ingresos extra del periodo (todo menos la nómina automática y los traspasos de cierre)
// amplían el presupuesto del mes: la meta pasa a ser metaMensual + ingresosExtra.
// Todo lo que no se pagó en efectivo (tarjeta, ingresos, gastos fijos, movimientos antiguos) cuenta como tarjeta.
class DivisionPresupuesto {
  final double saldo;
  final double meta; // Tope de la barra de gasto (incluye los ingresos extra)
  final double ingresosExtra;
  final double totalGastado; // Gasto del periodo actual en esta vista
  final Map<String, double> gastosPorCategoria;
  final List<Transaccion> movimientos;

  const DivisionPresupuesto._(this.saldo, this.meta, this.ingresosExtra, this.totalGastado, this.gastosPorCategoria, this.movimientos);

  static bool esEfectivo(Transaccion t) => t.metodoPago == AppStrings.metodoEfectivo;

  // Ingreso que amplía el presupuesto: no es la nómina automática ni un traspaso de cierre de mes
  static bool esIngresoExtra(Transaccion t) =>
      t.esIngreso &&
      t.concepto != AppStrings.nominaPartePresupuesto &&
      t.categoria != AppStrings.categoriaRemanente &&
      t.categoria != AppStrings.categoriaDeficit;

  static bool perteneceA(VistaPresupuesto vista, Transaccion t) {
    switch (vista) {
      case VistaPresupuesto.total:
        return true;
      case VistaPresupuesto.efectivo:
        return esEfectivo(t);
      case VistaPresupuesto.tarjeta:
        return !esEfectivo(t);
    }
  }

  factory DivisionPresupuesto.calcular({
    required List<Transaccion> transacciones,
    required VistaPresupuesto vista,
    required double metaMensual,
    required double limiteEfectivo,
    required DateTime inicioPeriodo,
  }) {
    // El gasto del periodo no incluye el traspaso del remanente
    bool esGastoDelPeriodo(Transaccion t) =>
        !t.esIngreso && !t.fecha.isBefore(inicioPeriodo) && t.categoria != AppStrings.categoriaRemanente;
    double euros(Transaccion t) => t.montoEnCentimos / AppNumbers.centimosEnEuro;

    double saldoTotal = 0;
    double gastoEfectivoPeriodo = 0;
    double ingresosExtra = 0;
    for (final t in transacciones) {
      saldoTotal += t.esIngreso ? euros(t) : -euros(t);
      if (esEfectivo(t) && esGastoDelPeriodo(t)) gastoEfectivoPeriodo += euros(t);
      if (esIngresoExtra(t) && !t.fecha.isBefore(inicioPeriodo)) ingresosExtra += euros(t);
    }
    final presupuesto = metaMensual + ingresosExtra;
    final efectivoRestante = limiteEfectivo - gastoEfectivoPeriodo;

    final movimientos = transacciones.where((t) => perteneceA(vista, t)).toList();
    double totalGastado = 0;
    final gastosPorCategoria = <String, double>{};
    for (final t in movimientos.where(esGastoDelPeriodo)) {
      totalGastado += euros(t);
      gastosPorCategoria[t.categoria] = (gastosPorCategoria[t.categoria] ?? 0) + euros(t);
    }

    final double saldo;
    final double meta;
    switch (vista) {
      case VistaPresupuesto.total:
        saldo = saldoTotal;
        meta = presupuesto;
      case VistaPresupuesto.efectivo:
        saldo = efectivoRestante;
        meta = limiteEfectivo;
      case VistaPresupuesto.tarjeta:
        saldo = limiteEfectivo > 0 ? saldoTotal - efectivoRestante : saldoTotal;
        meta = (presupuesto - limiteEfectivo).clamp(0, double.infinity).toDouble();
    }

    return DivisionPresupuesto._(saldo, meta, ingresosExtra, totalGastado, gastosPorCategoria, movimientos);
  }
}
