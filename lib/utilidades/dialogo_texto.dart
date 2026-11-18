import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';

// Diálogo con un único campo de texto. Devuelve el texto confirmado o null si se cancela.
// El controlador vive en el State del diálogo y se libera cuando el diálogo desaparece
// del todo (tras la animación de cierre), no justo al cerrarse: liberarlo antes provoca
// "TextEditingController was used after being disposed" / "_dependents.isEmpty".
Future<String?> mostrarDialogoTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  required String textoConfirmar,
  String valorInicial = '',
  String? ayuda,
  String? nota,
  String? sufijo,
  IconData? icono,
  TextInputType? teclado,
  TextCapitalization mayusculas = TextCapitalization.none,
  Future<bool> Function(String texto)? validar, // Si devuelve false, el diálogo no se cierra
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _DialogoTexto(
      titulo: titulo,
      etiqueta: etiqueta,
      textoConfirmar: textoConfirmar,
      valorInicial: valorInicial,
      ayuda: ayuda,
      nota: nota,
      sufijo: sufijo,
      icono: icono,
      teclado: teclado,
      mayusculas: mayusculas,
      validar: validar,
    ),
  );
}

class _DialogoTexto extends StatefulWidget {
  final String titulo;
  final String etiqueta;
  final String textoConfirmar;
  final String valorInicial;
  final String? ayuda;
  final String? nota;
  final String? sufijo;
  final IconData? icono;
  final TextInputType? teclado;
  final TextCapitalization mayusculas;
  final Future<bool> Function(String texto)? validar;

  const _DialogoTexto({
    required this.titulo,
    required this.etiqueta,
    required this.textoConfirmar,
    required this.valorInicial,
    required this.mayusculas,
    this.ayuda,
    this.nota,
    this.sufijo,
    this.icono,
    this.teclado,
    this.validar,
  });

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final TextEditingController _controlador = TextEditingController(text: widget.valorInicial);
  bool _guardando = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_guardando) return;
    final texto = _controlador.text.trim();
    setState(() => _guardando = true);
    final valido = widget.validar == null || await widget.validar!(texto);
    if (!mounted) return;
    if (valido) {
      Navigator.pop(context, texto);
    } else {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controlador,
            autofocus: true,
            keyboardType: widget.teclado,
            textCapitalization: widget.mayusculas,
            onSubmitted: (_) => _confirmar(),
            decoration: InputDecoration(
              labelText: widget.etiqueta,
              helperText: widget.ayuda,
              helperMaxLines: 2,
              suffixText: widget.sufijo,
              prefixIcon: widget.icono != null ? Icon(widget.icono) : null,
            ),
          ),
          if (widget.nota != null) ...[
            const SizedBox(height: AppNumbers.paddingCorto),
            Text(widget.nota!, style: const TextStyle(fontSize: AppNumbers.fontSizePequeno, color: Colors.grey)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelar)),
        ElevatedButton(onPressed: _guardando ? null : _confirmar, child: Text(widget.textoConfirmar)),
      ],
    );
  }
}
