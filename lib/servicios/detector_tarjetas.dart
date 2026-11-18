import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';

// Detecta la tarjeta usada en una notificación de pago de un wallet o de una app bancaria.
// Ej.: "Mercadona · 12,50 € con Visa ••1234" -> "Visa ••1234"
//
// EXPERIMENTAL: Google Wallet y Samsung Wallet no publican el formato de sus
// notificaciones y puede cambiar según versión e idioma.
class DetectorTarjetas {
  // Paquete de Android -> nombre del wallet
  static const Map<String, String> wallets = {
    'com.google.android.apps.walletnfcrel': 'Google Wallet',
    'com.samsung.android.spay': 'Samsung Wallet',
    'com.samsung.android.samsungpay.gear': 'Samsung Wallet',
  };

  static final Map<RegExp, String> _redes = {
    RegExp(r'\bvisa\b', caseSensitive: false): 'Visa',
    RegExp(r'\bmaster\s?card\b', caseSensitive: false): 'Mastercard',
    RegExp(r'\bmaestro\b', caseSensitive: false): 'Maestro',
    RegExp(r'\b(american express|amex)\b', caseSensitive: false): 'Amex',
    RegExp(r'\bdiscover\b', caseSensitive: false): 'Discover',
    RegExp(r'\bunion\s?pay\b', caseSensitive: false): 'UnionPay',
    RegExp(r'\bjcb\b', caseSensitive: false): 'JCB',
  };

  // Últimos 4 dígitos tras "••", "****", "xx", "...", "*1234" o "terminada en / ending in / se terminant par / endet auf"
  static final RegExp _ultimosDigitos = RegExp(
    r'(?:[•·∙●*xX]{2,}\s*|\.{2,}\s*|…\s*|(?<![\w*])\*\s?|(?:ending in|ending|terminada en|acabada en|finalizada en|que termina en|se terminant par|terminant par|endet auf|endend auf|mit endung)\s*)(\d{4})\b',
    caseSensitive: false,
  );

  static bool esWallet(String? paquete) => wallets.containsKey(paquete);

  // Red de la tarjeta mencionada en un texto ('Visa', 'Mastercard'…) o null
  static String? red(String texto) {
    for (final red in _redes.entries) {
      if (red.key.hasMatch(texto)) return red.value;
    }
    return null;
  }

  // Últimos 4 dígitos de la tarjeta mencionada en un texto o null
  static String? ultimosDigitos(String texto) => _ultimosDigitos.firstMatch(texto)?.group(1);

  // Wallets y apps bancarias del catálogo. En las bancarias el nombre lleva el banco
  // ("Visa BBVA ••1234"), igual que en el alta rápida, para no duplicar tarjetas.
  static String? detectar(String? paquete, String? titulo, String? texto) {
    final banco = CatalogoBancos.porPaquete(paquete);
    if (!esWallet(paquete) && banco == null) return null;
    final contenido = '${titulo ?? ''} ${texto ?? ''}';

    final digitos = ultimosDigitos(contenido);
    if (digitos == null) return null;
    if (banco != null) return [?red(contenido), banco.nombre, '••$digitos'].join(' ');
    return '${red(contenido) ?? wallets[paquete]!} ••$digitos';
  }
}
