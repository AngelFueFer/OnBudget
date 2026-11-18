import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/division_presupuesto.dart';

// Selector centrado Efectivo / Tarjeta / Total de la barra superior del Presupuesto Mensual.
// Misma forma y tamaño que los desplegables de Inversión y Ahorro: una píldora con tres segmentos.
class SelectorVistaPresupuesto extends StatelessWidget {
  final VistaPresupuesto vista;
  final ValueChanged<VistaPresupuesto> onCambio;

  const SelectorVistaPresupuesto({super.key, required this.vista, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final esquema = Theme.of(context).colorScheme;
    const radio = AppNumbers.altoSelectorBarra / 2;

    // Tarjeta a la izquierda, Total en el centro y Efectivo a la derecha
    final segmentos = [
      (VistaPresupuesto.tarjeta, l10n.vistaTarjeta, Icons.credit_card),
      (VistaPresupuesto.total, l10n.vistaTotal, null),
      (VistaPresupuesto.efectivo, l10n.efectivo, Icons.payments),
    ];

    return Container(
      width: AppNumbers.anchoSelectorBarra,
      height: AppNumbers.altoSelectorBarra,
      decoration: BoxDecoration(
        border: Border.all(color: esquema.outline),
        borderRadius: BorderRadius.circular(radio),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            for (var i = 0; i < segmentos.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: esquema.outline),
              Expanded(child: _segmento(context, segmentos[i].$1, segmentos[i].$2, segmentos[i].$3)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _segmento(BuildContext context, VistaPresupuesto valor, String texto, IconData? icono) {
    final esquema = Theme.of(context).colorScheme;
    final seleccionado = valor == vista;
    final color = seleccionado ? esquema.onSecondaryContainer : esquema.onSurface;

    return Semantics(
      selected: seleccionado,
      button: true,
      child: InkWell(
        onTap: () => onCambio(valor),
        child: Ink(
          color: seleccionado ? esquema.secondaryContainer : null,
          // FittedBox: en idiomas con palabras largas el texto se encoge en vez de desbordar
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icono != null) ...[Icon(icono, size: 16, color: color), const SizedBox(width: 4)],
                    Text(texto, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
