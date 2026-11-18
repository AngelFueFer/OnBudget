// Validación de la dirección del servidor propio que escribe el usuario
class UrlServidor {
  // Devuelve la URL limpia (sin barra final) o null si no es válida.
  // Sin esquema se asume https; http solo se admite si el usuario lo escribe (p. ej. red local).
  static String? normalizar(String texto) {
    var limpio = texto.trim();
    if (limpio.isEmpty || limpio.contains(' ')) return null;
    if (!limpio.contains('://')) limpio = 'https://$limpio';
    final uri = Uri.tryParse(limpio);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
    // Un host sin punto solo vale si es localhost (evita aceptar palabras sueltas)
    if (!uri.host.contains('.') && uri.host != 'localhost') return null;
    while (limpio.endsWith('/')) {
      limpio = limpio.substring(0, limpio.length - 1);
    }
    return limpio;
  }
}
