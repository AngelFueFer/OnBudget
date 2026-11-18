import 'package:presupuesto_familiar/modelos/extracto.dart';

// Lector de ficheros Norma 43 (Cuaderno 43 de la AEB), el formato de extracto que exportan
// casi todos los bancos españoles. Registros de 80 caracteres:
//   11 cabecera de cuenta (entidad, oficina, cuenta, saldo inicial)
//   22 movimiento (fecha, debe/haber, importe, referencias)
//   23 concepto complementario del movimiento anterior
//   33 final de cuenta (saldo final)
//   88 final de fichero
class ImportadorNorma43 {
  static bool pareceNorma43(String contenido) {
    final lineas = _lineas(contenido);
    return lineas.isNotEmpty && lineas.first.startsWith('11') && lineas.any((l) => l.startsWith('33'));
  }

  static List<ExtractoCuenta> leer(String contenido) {
    final cuentas = <ExtractoCuenta>[];
    String? entidad, oficina, numero;
    DateTime? fechaFinal;
    var movimientos = <MovimientoExtracto>[];
    // Concepto del movimiento en curso: se completa con los registros 23 que le siguen
    DateTime? fechaMov;
    double? importeMov;
    var conceptoMov = <String>[];
    var conComplementario = false;

    void cerrarMovimiento() {
      if (fechaMov != null && importeMov != null) {
        final concepto = conceptoMov.where((c) => c.isNotEmpty).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        movimientos.add(MovimientoExtracto(fecha: fechaMov!, concepto: concepto, importe: importeMov!));
      }
      fechaMov = null;
      importeMov = null;
      conceptoMov = [];
      conComplementario = false;
    }

    for (final linea in _lineas(contenido)) {
      final l = linea.padRight(80);
      switch (l.substring(0, 2)) {
        case '11':
          cerrarMovimiento();
          entidad = l.substring(2, 6);
          oficina = l.substring(6, 10);
          numero = l.substring(10, 20);
          fechaFinal = _fecha(l.substring(26, 32));
          movimientos = [];
        case '22':
          cerrarMovimiento();
          fechaMov = _fecha(l.substring(10, 16));
          final cargo = l[27] == '1';
          final importe = _importe(l.substring(28, 42));
          importeMov = cargo ? -importe : importe;
          // Las referencias del propio registro sirven de concepto si no llega ningún 23
          conceptoMov = [l.substring(52, 64).trim(), l.substring(64, 80).trim()];
        case '23':
          if (fechaMov != null) {
            // El primer 23 sustituye a las referencias, que suelen ser códigos internos
            if (!conComplementario) conceptoMov = [];
            conComplementario = true;
            conceptoMov.addAll([l.substring(4, 42).trim(), l.substring(42, 80).trim()]);
          }
        case '33':
          cerrarMovimiento();
          final deudor = l[58] == '1';
          final saldo = _importe(l.substring(59, 73));
          cuentas.add(ExtractoCuenta(
            entidad: entidad,
            oficina: oficina,
            numeroCuenta: numero,
            saldoFinal: deudor ? -saldo : saldo,
            fechaSaldo: fechaFinal,
            movimientos: movimientos,
          ));
          movimientos = [];
      }
    }
    if (cuentas.isEmpty) throw const FormatoExtractoNoValido('Sin registros 11/33 de Norma 43');
    return cuentas;
  }

  static List<String> _lineas(String contenido) =>
      contenido.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

  // 'AAMMDD' -> fecha (años 00-79 = 20xx)
  static DateTime _fecha(String aammdd) {
    final anio = int.parse(aammdd.substring(0, 2));
    return DateTime(anio < 80 ? 2000 + anio : 1900 + anio, int.parse(aammdd.substring(2, 4)), int.parse(aammdd.substring(4, 6)));
  }

  // 14 dígitos con 2 decimales implícitos
  static double _importe(String digitos) => int.parse(digitos.trim()) / 100;
}
