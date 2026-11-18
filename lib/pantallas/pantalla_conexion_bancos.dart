import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/servicios/open_banking/config_open_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';

// Configuración > Conexión con los bancos (Open Banking). Misma estructura que Conexión con los mercados.
class PantallaConexionBancos extends StatefulWidget {
  const PantallaConexionBancos({super.key});

  @override
  State<PantallaConexionBancos> createState() => _PantallaConexionBancosState();
}

class _PantallaConexionBancosState extends State<PantallaConexionBancos> {
  late final TextEditingController _id = TextEditingController(text: ConfigOpenBanking.idAplicacion);
  late final TextEditingController _clave = TextEditingController(text: ConfigOpenBanking.clavePrivada);
  late final TextEditingController _url = TextEditingController(text: ConfigOpenBanking.urlVuelta);
  late final TextEditingController _pais = TextEditingController(text: ConfigOpenBanking.pais);
  TipoProveedor _proveedor = ConfigOpenBanking.proveedor;
  bool _mostrarClave = false;
  bool _probando = false;

  static const Map<TipoProveedor, String> _nombres = {TipoProveedor.enableBanking: 'Enable Banking'};

  @override
  void dispose() {
    _id.dispose();
    _clave.dispose();
    _url.dispose();
    _pais.dispose();
    super.dispose();
  }

  Future<void> _guardarConfig() => ConfigOpenBanking.guardar(
        proveedor: _proveedor,
        idAplicacion: _id.text,
        clavePrivada: _clave.text,
        urlVuelta: _url.text,
        pais: _pais.text.isEmpty ? 'ES' : _pais.text,
      );

  Future<void> _guardar() async {
    final l10n = AppLocalizations.of(context);
    await _guardarConfig();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.configuracionGuardada)));
  }

  Future<void> _cargarClave() async {
    final ficheros = await FilePicker.pickFiles(type: FileType.any);
    if (ficheros.isEmpty) return;
    final texto = utf8.decode(await ficheros.first.readAsBytes(), allowMalformed: true);
    if (mounted) setState(() => _clave.text = texto.trim());
  }

  Future<void> _probar() async {
    final l10n = AppLocalizations.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    await _guardarConfig(); // Se prueba lo escrito
    if (!mounted) return;
    setState(() => _probando = true);
    bool correcta;
    try {
      correcta = await ConfigOpenBanking.crear().probarConexion();
    } on ErrorBancario {
      correcta = false;
    }
    if (!mounted) return;
    setState(() => _probando = false);
    mensajero.showSnackBar(SnackBar(
      content: Text(correcta ? l10n.conexionCorrecta : l10n.conexionBancosFallida),
      backgroundColor: correcta ? AppColors.exito : AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conexionBancos)),
      body: ListView(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        children: [
          Text(l10n.conexionBancosAyuda, style: TextStyle(fontSize: AppNumbers.fontSizeAyuda, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppNumbers.paddingStandard),
          DropdownButtonFormField<TipoProveedor>(
            initialValue: _proveedor,
            decoration: InputDecoration(
              labelText: l10n.proveedorBancario,
              prefixIcon: const Icon(Icons.hub),
              border: const OutlineInputBorder(),
            ),
            items: TipoProveedor.values.map((t) => DropdownMenuItem(value: t, child: Text(_nombres[t] ?? t.name))).toList(),
            onChanged: (t) {
              if (t != null) setState(() => _proveedor = t);
            },
          ),
          const SizedBox(height: AppNumbers.paddingMedio),
          TextField(
            controller: _id,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.idAplicacion,
              prefixIcon: const Icon(Icons.badge),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppNumbers.paddingMedio),
          TextField(
            controller: _clave,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: !_mostrarClave,
            maxLines: _mostrarClave ? 6 : 1,
            decoration: InputDecoration(
              labelText: l10n.clavePrivada,
              prefixIcon: const Icon(Icons.key),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(tooltip: l10n.cargarArchivo, icon: const Icon(Icons.upload_file), onPressed: _cargarClave),
                  IconButton(
                    icon: Icon(_mostrarClave ? Icons.visibility_off : Icons.visibility),
                    tooltip: _mostrarClave ? AppLocalizations.of(context).ocultarClave : AppLocalizations.of(context).mostrarClave,
                    onPressed: () => setState(() => _mostrarClave = !_mostrarClave),
                  ),
                ],
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppNumbers.paddingMedio),
          TextField(
            controller: _url,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l10n.urlVuelta,
              helperText: l10n.urlVueltaAyuda,
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppNumbers.paddingMedio),
          TextField(
            controller: _pais,
            textCapitalization: TextCapitalization.characters,
            maxLength: 2,
            decoration: InputDecoration(
              labelText: l10n.paisBancos,
              prefixIcon: const Icon(Icons.flag),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppNumbers.paddingCorto),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _probando ? null : _probar,
                  icon: _probando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: Text(l10n.probarConexion),
                ),
              ),
              const SizedBox(width: AppNumbers.paddingMedio),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save),
                  label: Text(l10n.guardar),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
