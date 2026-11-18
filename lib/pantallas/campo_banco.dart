import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';

// Círculo con el color e iniciales del banco; icono genérico si no es del catálogo
class AvatarBanco extends StatelessWidget {
  final BancoCatalogo? banco;
  final double radio;
  const AvatarBanco({super.key, this.banco, this.radio = 18});

  @override
  Widget build(BuildContext context) {
    final b = banco;
    if (b == null) {
      return CircleAvatar(radius: radio, child: Icon(Icons.account_balance, size: radio));
    }
    return CircleAvatar(
      radius: radio,
      backgroundColor: Color(b.color),
      child: Text(b.iniciales, style: TextStyle(color: Colors.white, fontSize: radio * 0.7, fontWeight: FontWeight.bold)),
    );
  }
}

// Si el texto coincide con el nombre o un alias de un banco del catálogo, lo devuelve
BancoCatalogo? bancoPorTexto(String texto) {
  final limpio = texto.trim().toLowerCase();
  if (limpio.isEmpty) return null;
  return CatalogoBancos.bancos.where((b) => [b.nombre, ...b.alias].any((n) => n.toLowerCase() == limpio)).firstOrNull;
}

// Campo de banco con sugerencias del catálogo (los 40 al enfocar); también admite cualquier otro nombre
class CampoBanco extends StatefulWidget {
  final TextEditingController controlador;
  final BancoCatalogo? banco; // El que se muestra en el avatar
  final ValueChanged<BancoCatalogo> alElegir;
  final VoidCallback? alEscribir;

  const CampoBanco({super.key, required this.controlador, required this.alElegir, this.banco, this.alEscribir});

  @override
  State<CampoBanco> createState() => _CampoBancoState();
}

class _CampoBancoState extends State<CampoBanco> {
  final FocusNode _foco = FocusNode();

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RawAutocomplete<BancoCatalogo>(
      textEditingController: widget.controlador,
      focusNode: _foco,
      displayStringForOption: (b) => b.nombre,
      optionsBuilder: (valor) => CatalogoBancos.buscar(valor.text),
      onSelected: widget.alElegir,
      fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
        controller: controlador,
        focusNode: foco,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => widget.alEscribir?.call(),
        decoration: InputDecoration(
          labelText: l10n.banco,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(AppNumbers.paddingCorto),
            child: AvatarBanco(banco: widget.banco ?? bancoPorTexto(controlador.text), radio: 14),
          ),
        ),
      ),
      optionsViewBuilder: (context, alElegir, opciones) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: opciones
                  .map((b) => ListTile(
                        dense: true,
                        leading: AvatarBanco(banco: b, radio: 14),
                        title: Text(b.nombre),
                        subtitle: b.neobanco ? Text(l10n.neobanco) : null,
                        onTap: () => alElegir(b),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
