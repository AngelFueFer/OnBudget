// ISIN (ISO 6166): 2 letras de país + 9 caracteres alfanuméricos + 1 dígito de control.
// Ej.: ES0113900J37 (Banco Santander), US0378331005 (Apple).
class Isin {
  static final RegExp _formato = RegExp(r'^[A-Z]{2}[A-Z0-9]{9}[0-9]$');

  // Tiene forma de ISIN (aunque el dígito de control sea incorrecto)
  static bool pareceIsin(String texto) => _formato.hasMatch(texto.trim().toUpperCase());

  // Forma correcta y dígito de control válido (algoritmo de Luhn sobre los dígitos expandidos)
  static bool esValido(String texto) {
    final isin = texto.trim().toUpperCase();
    if (!_formato.hasMatch(isin)) return false;

    // Cada letra se sustituye por su valor (A=10 … Z=35)
    final digitos = isin.split('').map((c) {
      final codigo = c.codeUnitAt(0);
      return codigo >= 65 ? '${codigo - 55}' : c;
    }).join();

    var suma = 0;
    var duplicar = false;
    for (var i = digitos.length - 1; i >= 0; i--) {
      var n = int.parse(digitos[i]);
      if (duplicar) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      suma += n;
      duplicar = !duplicar;
    }
    return suma % 10 == 0;
  }
}
