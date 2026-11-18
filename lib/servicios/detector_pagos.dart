import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/servicios/detector_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/importador_csv.dart';

// Pago leído de la notificación de una app bancaria, pendiente de que el usuario lo confirme.
class PagoDetectado {
  final DateTime fecha;
  final double importe;
  final String comercio;
  final String bancoId;
  final String? ultimos4;

  const PagoDetectado({required this.fecha, required this.importe, required this.comercio, required this.bancoId, this.ultimos4});

  // Una app puede repetir la misma notificación: mismo minuto, importe y comercio = mismo pago
  String get clave =>
      '$bancoId|${fecha.toIso8601String().substring(0, 16)}|${importe.toStringAsFixed(2)}|${comercio.toLowerCase()}';

  int get centimos => (importe * 100).round();

  // La misma notificación vuelta a publicar (o actualizada) unos minutos después
  static const Duration margenRepetida = Duration(minutes: 5);

  bool mismoPago(PagoDetectado otro) =>
      bancoId == otro.bancoId &&
      centimos == otro.centimos &&
      comercio.trim().toLowerCase() == otro.comercio.trim().toLowerCase() &&
      fecha.difference(otro.fecha).abs() <= margenRepetida;

  Map<String, dynamic> toJson() => {
        'fecha': fecha.toIso8601String(),
        'importe': importe,
        'comercio': comercio,
        'bancoId': bancoId,
        if (ultimos4 != null) 'ultimos4': ultimos4,
      };

  factory PagoDetectado.fromJson(Map<String, dynamic> json) => PagoDetectado(
        fecha: DateTime.parse(json['fecha']),
        importe: (json['importe'] as num).toDouble(),
        comercio: json['comercio'],
        bancoId: json['bancoId'],
        ultimos4: json['ultimos4'],
      );
}

// Detecta pagos en las notificaciones de las apps bancarias del catálogo y de las apps de pago (PayPal…).
// Ej.: "Compra de 12,50 € en MERCADONA con tarjeta ••1234", "Paid €4.50 at Starbucks",
// "Has pagado 10,00 € a Amazon", "Has enviado un Bizum de 15,00 € a Ana".
//
// EXPERIMENTAL: los bancos no publican el formato de sus notificaciones y cambia según versión e idioma.
// Solo se proponen gastos; ingresos, devoluciones y transferencias recibidas se ignoran.
class DetectorPagos {
  // Apps de pago que no son bancos del catálogo: paquete de Android -> nombre
  static const Map<String, String> appsPago = {
    'com.paypal.android.p2pmobile': 'PayPal',
    'com.imaginecurve.curve.prod': 'Curve',
    'com.myklarnamobile': 'Klarna',
  };

  // Origen del pago (id y nombre) para un paquete, o null si no se escucha
  static ({String id, String nombre})? origen(String? paquete) {
    final banco = CatalogoBancos.porPaquete(paquete);
    if (banco != null) return (id: banco.id, nombre: banco.nombre);
    final app = appsPago[paquete];
    return app == null ? null : (id: app.toLowerCase(), nombre: app);
  }

  static final RegExp _esPago = RegExp(
    r'compra|pago|cargo|has pagado|has gastado|has enviado|\bbizum\b|\bpaid\b|payment|purchase|\bspent\b|you sent|achat|paiement|zahlung|bezahlt',
    caseSensitive: false,
  );

  static final RegExp _noEsGasto = RegExp(
    r'recibid|ingreso|abono|devoluci|reembolso|\breceived\b|refund|\breçu\b|remboursement|erhalten|gutschrift|rechazad|denegad|declined',
    caseSensitive: false,
  );

  static const String _numero = r'(\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)';
  static final RegExp _importe = RegExp('(?:(?:€|EUR)\\s?$_numero)|(?:$_numero\\s?(?:€|EUR|euros?))', caseSensitive: false);

  // "terminada en 1234 en MERCADONA": un número suelto no es un comercio, se busca el siguiente "en"
  static final RegExp _comercio = RegExp(
    r"\b(?:en|at|in|chez|bei)\s+(?!\d+\b)([A-Za-zÀ-ÿ0-9&'.\-*][A-Za-zÀ-ÿ0-9&'.\-* ]{1,40}?)(?=\s+(?:con|with|el|on|le|am|mit|por|using|avec)\b|\s*[,;:!(]|\.\s|\.$|\s*$)",
    caseSensitive: false,
  );

  // Destinatario justo después del importe: "10,00 € a Amazon", "€10.00 EUR to John"
  static final RegExp _destinatario = RegExp(
    r"(?:€|EUR|euros?)\s+(?:EUR\s+)?(?:a|to|à|an)\s+([A-Za-zÀ-ÿ0-9&'.\-*][A-Za-zÀ-ÿ0-9&'.\-* ]{1,40}?)(?=\s+(?:con|with|el|on|le|am|mit|por|using|avec|desde|from)\b|\s*[,;:!(]|\.\s|\.$|\s*$)",
    caseSensitive: false,
  );

  // Recibos domiciliados: "Cargo de 45,20 € del recibo de IBERDROLA"
  static final RegExp _emisorRecibo = RegExp(
    r"\b(?:recibo|domiciliaci[oó]n|adeudo)\s+(?:de\s+|del\s+)?([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9&'.\-* ]{1,40}?)(?=\s+(?:con|por|el)\b|\s*[,;:!(]|\.\s|\.$|\s*$)",
    caseSensitive: false,
  );

  // Importe con signo menos ("-12,50 € bei REWE"): las apps que no dicen "compra" lo marcan así
  static final RegExp _importeNegativo = RegExp('(?:^|[\\s(])[-−–]\\s?(?:€|EUR)?\\s?\\d');

  static final RegExp _avisoSaldo = RegExp(r'saldo|balance|kontostand|solde', caseSensitive: false);

  static PagoDetectado? detectar(String? paquete, String? titulo, String? texto, {DateTime? ahora}) {
    final origen = DetectorPagos.origen(paquete);
    if (origen == null) return null;
    final contenido = '${titulo ?? ''} ${texto ?? ''}'.trim();
    if (_noEsGasto.hasMatch(contenido)) return null;
    // Un aviso de saldo en negativo ("Tu saldo es -50,00 €") no es un pago
    final porSigno = _importeNegativo.hasMatch(contenido) && !_avisoSaldo.hasMatch(contenido);
    if (!_esPago.hasMatch(contenido) && !porSigno) return null;

    final coincidencia = _importe.firstMatch(contenido);
    if (coincidencia == null) return null;
    final importe = ImportadorCsv.leerNumero(coincidencia.group(1) ?? coincidencia.group(2)!);
    if (importe == null || importe <= 0) return null;

    var comercio = _comercio.firstMatch(texto ?? '')?.group(1)?.trim() ??
        _comercio.firstMatch(contenido)?.group(1)?.trim() ??
        _destinatario.firstMatch(contenido)?.group(1)?.trim();
    // "en tu tarjeta" / "in your account" no son comercios
    if (comercio != null && RegExp(r'^(tu|su|your|votre|deine?)\b', caseSensitive: false).hasMatch(comercio)) comercio = null;
    comercio ??= _emisorRecibo.firstMatch(contenido)?.group(1)?.trim();
    // "MERCADONA 12,50 €" con el título "Compra con tarjeta": lo que queda del texto sin el importe
    final restoTexto = (texto ?? '').replaceAll(_importe, '').replaceAll(RegExp(r'[-−–]'), '').trim();
    if (comercio == null &&
        restoTexto.length >= 2 &&
        restoTexto.length <= 40 &&
        RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(restoTexto) &&
        !_esPago.hasMatch(restoTexto) &&
        !RegExp(r'\d{4}').hasMatch(restoTexto)) {
      comercio = restoTexto;
    }
    // Sin comercio en el texto, el título suele serlo (ej. Revolut: título "Starbucks")
    final tituloLimpio = titulo?.trim() ?? '';
    if (comercio == null && tituloLimpio.isNotEmpty && !_esPago.hasMatch(tituloLimpio) && !_importe.hasMatch(tituloLimpio)) {
      comercio = tituloLimpio;
    }

    return PagoDetectado(
      fecha: ahora ?? DateTime.now(),
      importe: importe,
      comercio: comercio ?? origen.nombre,
      bancoId: origen.id,
      ultimos4: DetectorTarjetas.ultimosDigitos(contenido),
    );
  }
}
