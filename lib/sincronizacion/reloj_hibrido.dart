// Reloj lógico híbrido (HLC): ordena los cambios de varios dispositivos aunque sus relojes
// no coincidan. Combina la hora física con un contador, y el id del dispositivo desempata.
//
// Formato de texto: "<milisegundos, 15 dígitos>-<contador, 4 dígitos hex>-<dispositivo>".
// Al tener ancho fijo, comparar dos textos (compareTo) equivale a comparar los relojes.
class RelojHibrido {
  static const int _digitosMs = 15;
  static const int _digitosContador = 4;
  static const int _contadorMaximo = 0xFFFF;
  static const String _separador = '-';

  final String dispositivo;
  // Sustituible en tests para controlar la hora
  final DateTime Function() _ahora;

  int _ms = 0;
  int _contador = 0;

  RelojHibrido(this.dispositivo, {DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now;

  // Marca para un cambio hecho en este dispositivo; siempre mayor que la anterior
  String siguiente() {
    final fisico = _ahora().millisecondsSinceEpoch;
    if (fisico > _ms) {
      _ms = fisico;
      _contador = 0;
    } else {
      _incrementarContador();
    }
    return _formatear(_ms, _contador, dispositivo);
  }

  // Ajusta el reloj al recibir una marca de otro dispositivo, para que lo próximo que se
  // escriba aquí quede por delante de lo recibido aunque el otro móvil vaya adelantado.
  void recibir(String remota) {
    final otra = RelojHibrido.leer(remota);
    if (otra == null) return;
    final fisico = _ahora().millisecondsSinceEpoch;
    final maximo = [_ms, otra.ms, fisico].reduce((a, b) => a > b ? a : b);
    if (maximo == _ms && maximo == otra.ms) {
      _contador = (_contador > otra.contador ? _contador : otra.contador);
      _incrementarContador();
    } else if (maximo == _ms) {
      _incrementarContador();
    } else if (maximo == otra.ms) {
      _contador = otra.contador;
      _incrementarContador();
    } else {
      _contador = 0;
    }
    _ms = maximo;
  }

  void _incrementarContador() {
    if (_contador >= _contadorMaximo) {
      // Contador agotado en el mismo milisegundo: se avanza el tiempo lógico
      _ms++;
      _contador = 0;
    } else {
      _contador++;
    }
  }

  static String _formatear(int ms, int contador, String dispositivo) =>
      '${ms.toString().padLeft(_digitosMs, '0')}$_separador'
      '${contador.toRadixString(16).padLeft(_digitosContador, '0')}$_separador$dispositivo';

  // Devuelve null si el texto no es una marca válida (datos corruptos o de otra versión)
  static ({int ms, int contador, String dispositivo})? leer(String marca) {
    final partes = marca.split(_separador);
    if (partes.length < 3) return null;
    final ms = int.tryParse(partes[0]);
    final contador = int.tryParse(partes[1], radix: 16);
    if (ms == null || contador == null) return null;
    // El id del dispositivo (uuid) también lleva guiones
    return (ms: ms, contador: contador, dispositivo: partes.sublist(2).join(_separador));
  }

  // true si a es posterior a b (null cuenta como "nunca escrito")
  static bool esPosterior(String? a, String? b) {
    if (a == null) return false;
    if (b == null) return true;
    return a.compareTo(b) > 0;
  }
}
