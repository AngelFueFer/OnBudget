import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/main.dart';

// Configuración > Temas: modo claro/oscuro y color de acento en un mismo sitio
class PantallaTemas extends StatelessWidget {
  const PantallaTemas({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.temas)),
      // Escucha los notificadores para reflejar el cambio al instante
      body: ListenableBuilder(
        listenable: Listenable.merge([themeNotifier, acentoNotifier]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(AppNumbers.paddingStandard),
            children: [
              SwitchListTile(
                title: Text(l10n.modoOscuro),
                subtitle: Text(l10n.modoOscuroDescripcion),
                secondary: Icon(Icons.dark_mode, color: esquema.primary),
                value: themeNotifier.value == ThemeMode.dark,
                onChanged: cambiarModoOscuro,
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppNumbers.paddingCorto),
                child: Text(l10n.colorAcento, style: TextStyle(fontWeight: FontWeight.bold, color: esquema.primary)),
              ),
              SelectorAcento(
                seleccionado: acentoNotifier.value,
                onSeleccionar: cambiarAcento,
              ),
              if (acentoNotifier.value == AppStrings.acentoBlanco)
                Padding(
                  padding: const EdgeInsets.only(top: AppNumbers.paddingMedio),
                  child: Text(l10n.acentoBlancoNota, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
            ],
          );
        },
      ),
    );
  }
}

// Fila de círculos de color con su nombre; el elegido lleva una marca
class SelectorAcento extends StatelessWidget {
  final String seleccionado;
  final ValueChanged<String> onSeleccionar;

  const SelectorAcento({super.key, required this.seleccionado, required this.onSeleccionar});

  static const double _tamanoCirculo = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final esquema = Theme.of(context).colorScheme;

    return Wrap(
      spacing: AppNumbers.paddingStandard,
      runSpacing: AppNumbers.paddingStandard,
      children: AppColors.coloresAcento.entries.map((acento) {
        final elegido = acento.key == seleccionado;
        // El círculo blanco necesita borde para verse sobre fondo claro
        final colorMarca = ThemeData.estimateBrightnessForColor(acento.value) == Brightness.light ? Colors.black : Colors.white;
        return Semantics(
          button: true,
          selected: elegido,
          label: l10n.nombreAcento(acento.key),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppNumbers.radiusStandard),
            onTap: () => onSeleccionar(acento.key),
            child: Padding(
              padding: const EdgeInsets.all(AppNumbers.paddingCorto / 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: _tamanoCirculo,
                    height: _tamanoCirculo,
                    decoration: BoxDecoration(
                      color: acento.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: elegido ? esquema.primary : esquema.outlineVariant,
                        width: elegido ? 3 : 1,
                      ),
                    ),
                    child: elegido ? Icon(Icons.check, color: colorMarca) : null,
                  ),
                  const SizedBox(height: AppNumbers.paddingCorto / 2),
                  ExcludeSemantics(
                    child: Text(l10n.nombreAcento(acento.key), style: const TextStyle(fontSize: AppNumbers.fontSizePequeno)),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
