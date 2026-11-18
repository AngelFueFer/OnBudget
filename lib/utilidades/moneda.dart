import 'package:flutter/widgets.dart';

// Moneda principal de la app. Solo cambia cómo se muestran los importes:
// los valores guardados no se convierten entre divisas.
class Moneda {
  final String codigo;
  final String simbolo;
  final int decimales;
  final bool simboloDelante;

  const Moneda(this.codigo, this.simbolo, this.decimales, this.simboloDelante);

  static const Moneda eur = Moneda('EUR', '€', 2, false);
  static const Moneda usd = Moneda('USD', '\$', 2, true);
  static const Moneda gbp = Moneda('GBP', '£', 2, true);
  static const Moneda cny = Moneda('CNY', 'CN¥', 2, true);
  static const Moneda jpy = Moneda('JPY', '¥', 0, true);

  static const List<Moneda> disponibles = [eur, usd, gbp, cny, jpy];
  static const Moneda porDefecto = eur;

  static Moneda desdeCodigo(String? codigo) {
    return disponibles.firstWhere((m) => m.codigo == codigo, orElse: () => porDefecto);
  }

  // Moneda actual; el widget que la consulta se reconstruye si cambia
  static Moneda of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MonedaScope>()?.notifier?.value ?? porDefecto;
  }

  // 12.5 -> '12.50 €' / '$12.50' / '¥13'
  String formatear(double valor, {bool conSigno = false, int? decimales}) {
    final signo = valor < 0 ? '-' : (conSigno ? '+' : '');
    final numero = valor.abs().toStringAsFixed(decimales ?? this.decimales);
    return simboloDelante ? '$signo$simbolo$numero' : '$signo$numero $simbolo';
  }
}

class MonedaScope extends InheritedNotifier<ValueNotifier<Moneda>> {
  const MonedaScope({super.key, required super.notifier, required super.child});
}
