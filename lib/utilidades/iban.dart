// IBAN (ISO 13616): 2 letras de país + 2 dígitos de control + código de cuenta nacional (BBAN).
// Ej.: ES91 2100 0418 4502 0005 1332 (CaixaBank).
// En España el BBAN es el CCC: entidad (4) + oficina (4) + DC (2) + cuenta (10).
class Iban {
  // Longitud total por país (los más habituales en bancos y neobancos que se usan en España)
  static const Map<String, int> longitudes = {
    'ES': 24, 'DE': 22, 'LT': 20, 'NL': 18, 'BE': 16, 'FR': 27, 'PT': 25,
    'IT': 27, 'GB': 22, 'IE': 22, 'LU': 20, 'AT': 20, 'AD': 24,
  };

  // Posición y longitud del código de banco dentro del IBAN, por país
  static const Map<String, (int, int)> _codigoBanco = {
    'ES': (4, 4), // entidad BdE
    'DE': (4, 8), // BLZ
    'LT': (4, 5),
    'NL': (4, 4), // BIC abreviado (ej. BUNQ)
    'BE': (4, 3),
    'FR': (4, 5),
    'PT': (4, 4),
    'IT': (5, 5),
    'GB': (4, 4),
    'IE': (4, 4),
    'LU': (4, 3),
    'AT': (4, 5),
    'AD': (4, 4),
  };

  static final RegExp _formato = RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$');

  // Quita espacios, guiones y pasa a mayúsculas
  static String normalizar(String texto) => texto.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static String pais(String texto) {
    final iban = normalizar(texto);
    return iban.length >= 2 ? iban.substring(0, 2) : '';
  }

  // Forma correcta, longitud del país (si se conoce) y dígitos de control mod 97.
  // En IBAN españoles comprueba también los dígitos de control del CCC.
  static bool esValido(String texto) {
    final iban = normalizar(texto);
    if (!_formato.hasMatch(iban)) return false;
    final longitud = longitudes[iban.substring(0, 2)];
    if (longitud != null && iban.length != longitud) return false;
    if (_mod97(iban) != 1) return false;
    if (iban.startsWith('ES') && !cccValido(iban)) return false;
    return true;
  }

  // Dígitos de control internos del CCC español (posiciones 13-14 del IBAN)
  static bool cccValido(String texto) {
    final iban = normalizar(texto);
    if (iban.length != 24 || !iban.startsWith('ES')) return false;
    final entidadOficina = iban.substring(4, 12);
    final dc = iban.substring(12, 14);
    final cuenta = iban.substring(14, 24);
    if (!RegExp(r'^\d+$').hasMatch(entidadOficina + dc + cuenta)) return false;
    return '${_digitoCcc('00$entidadOficina')}${_digitoCcc(cuenta)}' == dc;
  }

  // Código del banco según el país (entidad BdE en España, BLZ en Alemania…); null si no se reconoce
  static String? codigoBanco(String texto) {
    final iban = normalizar(texto);
    final posicion = _codigoBanco[pais(iban)];
    if (posicion == null) return null;
    final (inicio, largo) = posicion;
    if (iban.length < inicio + largo) return null;
    return iban.substring(inicio, inicio + largo);
  }

  // 'ES9121000418450200051332' -> 'ES91 2100 0418 4502 0005 1332'
  static String formatear(String texto) {
    final iban = normalizar(texto);
    final grupos = <String>[];
    for (var i = 0; i < iban.length; i += 4) {
      grupos.add(iban.substring(i, i + 4 > iban.length ? iban.length : i + 4));
    }
    return grupos.join(' ');
  }

  // 'ES91 •••• •••• •••• •••• 1332': país y control al principio, últimos 4 al final
  static String enmascarar(String texto) {
    final iban = normalizar(texto);
    if (iban.length < 8) return iban;
    final ocultos = ((iban.length - 8) / 4).ceil();
    return [iban.substring(0, 4), for (var i = 0; i < ocultos; i++) '••••', iban.substring(iban.length - 4)].join(' ');
  }

  // Mueve los 4 primeros caracteres al final, letras -> números (A=10 … Z=35) y resto entre 97
  static int _mod97(String iban) {
    final reordenado = iban.substring(4) + iban.substring(0, 4);
    var resto = 0;
    for (final c in reordenado.codeUnits) {
      final valor = c >= 65 ? c - 55 : c - 48;
      resto = (valor >= 10 ? resto * 100 + valor : resto * 10 + valor) % 97;
    }
    return resto;
  }

  static int _digitoCcc(String diezDigitos) {
    const pesos = [1, 2, 4, 8, 5, 10, 9, 7, 3, 6];
    var suma = 0;
    for (var i = 0; i < 10; i++) {
      suma += int.parse(diezDigitos[i]) * pesos[i];
    }
    final digito = 11 - suma % 11;
    if (digito == 11) return 0;
    if (digito == 10) return 1;
    return digito;
  }
}
