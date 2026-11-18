import 'package:presupuesto_familiar/modelos/extracto.dart';

// Lector de extractos en CSV (Revolut, N26, bunq, Wise, Trade Republic y la exportación CSV de
// la mayoría de bancos). En lugar de un perfil fijo por banco, reconoce las columnas por su
// cabecera en español, inglés, francés o alemán.
class ImportadorCsv {
  static const _fecha = ['fecha operacion', 'fecha operación', 'fecha', 'started date', 'completed date', 'booking date', 'date', 'datum', 'buchungsdatum', 'value date'];
  static const _concepto = ['concepto', 'descripcion', 'descripción', 'description', 'payee', 'partner name', 'merchant', 'counterparty', 'name', 'libellé', 'libelle', 'beschreibung', 'empfänger', 'movimiento'];
  static const _importe = ['importe', 'amount (eur)', 'amount', 'cantidad', 'montant', 'betrag'];
  static const _cargo = ['cargo', 'debe', 'debit', 'débit', 'soll', 'paid out'];
  static const _abono = ['abono', 'haber', 'credit', 'crédit', 'haben', 'paid in'];
  static const _saldo = ['saldo', 'balance', 'solde', 'kontostand'];
  static const _estado = ['state', 'estado', 'status'];
  static const _estadosDescartados = ['reverted', 'declined', 'failed', 'revertido', 'rechazado', 'cancelled'];

  static ExtractoCuenta leer(String contenido) {
    final lineas = contenido.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lineas.isEmpty) throw const FormatoExtractoNoValido('Fichero vacío');

    // La cabecera puede no ser la primera línea (algunos bancos ponen el título o el titular antes)
    for (var i = 0; i < lineas.length && i < 15; i++) {
      final separador = _separador(lineas[i]);
      final cabecera = _celdas(lineas[i], separador).map(_normalizar).toList();
      final colFecha = _buscar(cabecera, _fecha);
      final colImporte = _buscar(cabecera, _importe);
      final colCargo = _buscar(cabecera, _cargo);
      final colAbono = _buscar(cabecera, _abono);
      if (colFecha == null || (colImporte == null && (colCargo == null || colAbono == null))) continue;

      return _leerFilas(
        lineas.sublist(i + 1),
        separador,
        colFecha: colFecha,
        colConcepto: _buscar(cabecera, _concepto),
        colImporte: colImporte,
        colCargo: colCargo,
        colAbono: colAbono,
        colSaldo: _buscar(cabecera, _saldo),
        colEstado: _buscar(cabecera, _estado),
      );
    }
    throw const FormatoExtractoNoValido('No se reconocen las columnas de fecha e importe');
  }

  static ExtractoCuenta _leerFilas(
    List<String> filas,
    String separador, {
    required int colFecha,
    int? colConcepto,
    int? colImporte,
    int? colCargo,
    int? colAbono,
    int? colSaldo,
    int? colEstado,
  }) {
    final movimientos = <MovimientoExtracto>[];
    final saldos = <double?>[];
    for (final fila in filas) {
      final celdas = _celdas(fila, separador);
      String celda(int? col) => col != null && col < celdas.length ? celdas[col].trim() : '';

      if (_estadosDescartados.contains(celda(colEstado).toLowerCase())) continue;
      final fecha = leerFecha(celda(colFecha));
      if (fecha == null) continue;

      double? importe;
      if (colImporte != null) {
        importe = leerNumero(celda(colImporte));
      } else {
        final cargo = leerNumero(celda(colCargo));
        final abono = leerNumero(celda(colAbono));
        if (cargo != null && cargo != 0) importe = -cargo.abs();
        if (abono != null && abono != 0) importe = abono.abs();
      }
      if (importe == null || importe == 0) continue;

      movimientos.add(MovimientoExtracto(fecha: fecha, concepto: celda(colConcepto), importe: importe));
      saldos.add(leerNumero(celda(colSaldo)));
    }
    if (movimientos.isEmpty) throw const FormatoExtractoNoValido('Sin movimientos');

    // El saldo final es el del movimiento más reciente (el fichero puede venir en cualquier orden)
    final descendente = movimientos.first.fecha.isAfter(movimientos.last.fecha);
    final indiceUltimo = descendente ? 0 : movimientos.length - 1;
    return ExtractoCuenta(
      saldoFinal: saldos[indiceUltimo],
      fechaSaldo: saldos[indiceUltimo] == null ? null : movimientos[indiceUltimo].fecha,
      movimientos: movimientos,
    );
  }

  // '1.234,56' / '1,234.56' / '-12.50' / '12,5 €' -> número
  static double? leerNumero(String texto) {
    var t = texto.replaceAll(RegExp(r'[^\d,.\-+]'), '');
    if (t.isEmpty || !RegExp(r'\d').hasMatch(t)) return null;
    final ultimaComa = t.lastIndexOf(',');
    final ultimoPunto = t.lastIndexOf('.');
    if (ultimaComa >= 0 && ultimoPunto >= 0) {
      // El separador que aparece el último es el decimal
      t = ultimaComa > ultimoPunto ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
    } else if (ultimaComa >= 0) {
      // '12,5' / '12,50' -> decimal; '1,234' -> miles
      t = RegExp(r',\d{1,2}$').hasMatch(t) ? t.replaceAll(',', '.') : t.replaceAll(',', '');
    } else if (ultimoPunto >= 0 && RegExp(r'\.\d{3}$').hasMatch(t)) {
      t = t.replaceAll('.', ''); // '12.500' -> miles
    }
    return double.tryParse(t);
  }

  // 'AAAA-MM-DD[ hh:mm]', 'DD/MM/AAAA', 'DD-MM-AAAA', 'DD.MM.AAAA', 'DD/MM/AA'
  static DateTime? leerFecha(String texto) {
    final t = texto.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (iso != null) return _crearFecha(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    final europea = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(t);
    if (europea != null) {
      var anio = int.parse(europea[3]!);
      if (anio < 100) anio += 2000;
      return _crearFecha(anio, int.parse(europea[2]!), int.parse(europea[1]!));
    }
    return null;
  }

  static DateTime? _crearFecha(int anio, int mes, int dia) {
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    return DateTime(anio, mes, dia);
  }

  static String _separador(String linea) {
    const candidatos = [';', ',', '\t'];
    var mejor = ',';
    var maximo = 0;
    for (final c in candidatos) {
      final n = _celdas(linea, c).length;
      if (n > maximo) {
        maximo = n;
        mejor = c;
      }
    }
    return mejor;
  }

  // Separa una línea respetando las comillas ("Mercadona, S.A.")
  static List<String> _celdas(String linea, String separador) {
    final celdas = <String>[];
    final actual = StringBuffer();
    var entreComillas = false;
    for (var i = 0; i < linea.length; i++) {
      final c = linea[i];
      if (c == '"') {
        if (entreComillas && i + 1 < linea.length && linea[i + 1] == '"') {
          actual.write('"');
          i++;
        } else {
          entreComillas = !entreComillas;
        }
      } else if (c == separador && !entreComillas) {
        celdas.add(actual.toString());
        actual.clear();
      } else {
        actual.write(c);
      }
    }
    celdas.add(actual.toString());
    return celdas;
  }

  static String _normalizar(String texto) => texto.trim().toLowerCase().replaceAll('﻿', '');

  // Primera columna cuyo nombre coincide con alguna clave, por orden de preferencia de las claves
  static int? _buscar(List<String> cabecera, List<String> claves) {
    for (final clave in claves) {
      final exacta = cabecera.indexOf(clave);
      if (exacta >= 0) return exacta;
    }
    for (final clave in claves) {
      final parcial = cabecera.indexWhere((c) => c.startsWith(clave));
      if (parcial >= 0) return parcial;
    }
    return null;
  }
}
