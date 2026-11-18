// Frena los intentos de adivinar la contraseña: tras N fallos desde la misma IP en la ventana,
// se rechazan más intentos hasta que pase el tiempo. En memoria: se reinicia con el servidor.
class LimitadorIntentos {
  final int maximo;
  final Duration ventana;
  final DateTime Function() ahora;
  final Map<String, List<DateTime>> _fallos = {};

  LimitadorIntentos({required this.maximo, required this.ventana, DateTime Function()? ahora})
    : ahora = ahora ?? DateTime.now;

  bool bloqueado(String clave) => _recientes(clave).length >= maximo;

  void registrarFallo(String clave) => _fallos.putIfAbsent(clave, () => []).add(ahora());

  void limpiar(String clave) => _fallos.remove(clave);

  List<DateTime> _recientes(String clave) {
    final lista = _fallos[clave];
    if (lista == null) return const [];
    final limite = ahora().subtract(ventana);
    lista.removeWhere((t) => t.isBefore(limite));
    if (lista.isEmpty) _fallos.remove(clave);
    return lista;
  }
}
