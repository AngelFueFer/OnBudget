import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/servicios/api_bolsa.dart';
import 'package:presupuesto_familiar/servicios/config_mercados.dart';

// Configuración > Conexión con los mercados
class PantallaMercados extends StatefulWidget {
  const PantallaMercados({super.key});

  @override
  State<PantallaMercados> createState() => _PantallaMercadosState();
}

class _PantallaMercadosState extends State<PantallaMercados> {
  late final TextEditingController _clave = TextEditingController(text: ConfigMercados.clave);
  bool _activa = ConfigMercados.activa;
  bool _mostrarClave = false;
  bool _probando = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _cambiarActiva(bool valor) async {
    await ConfigMercados.cambiarActiva(valor);
    setState(() => _activa = valor);
  }

  Future<void> _guardarClave() async {
    final l10n = AppLocalizations.of(context);
    await ConfigMercados.guardarClave(_clave.text);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.claveGuardada)));
  }

  Future<void> _probar() async {
    final l10n = AppLocalizations.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    await ConfigMercados.guardarClave(_clave.text); // Se prueba la clave escrita
    if (!mounted) return;
    setState(() => _probando = true);
    final correcta = await ApiBolsa.probarConexion();
    if (!mounted) return;
    setState(() => _probando = false);
    mensajero.showSnackBar(SnackBar(
      content: Text(correcta ? l10n.conexionCorrecta : l10n.conexionFallida),
      backgroundColor: correcta ? AppColors.exito : AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conexionMercados)),
      body: ListView(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(_activa ? Icons.cloud_done : Icons.cloud_off, color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: Text(l10n.conectarServidores),
            subtitle: Text(l10n.conectarServidoresDescripcion),
            value: _activa,
            onChanged: _cambiarActiva,
          ),
          const Divider(),
          const SizedBox(height: AppNumbers.paddingCorto),
          // La clave solo tiene sentido con la conexión activada
          TextField(
            controller: _clave,
            enabled: _activa,
            obscureText: !_mostrarClave,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _guardarClave(),
            decoration: InputDecoration(
              labelText: l10n.claveApi,
              helperText: ConfigMercados.tieneClave ? l10n.usandoClavePropia : l10n.sinClaveApi,
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_mostrarClave ? Icons.visibility_off : Icons.visibility),
                tooltip: _mostrarClave ? AppLocalizations.of(context).ocultarClave : AppLocalizations.of(context).mostrarClave,
                onPressed: () => setState(() => _mostrarClave = !_mostrarClave),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppNumbers.paddingCorto),
          Text(l10n.claveApiAyuda, style: TextStyle(fontSize: AppNumbers.fontSizeAyuda, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppNumbers.paddingStandard),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _activa && !_probando ? _probar : null,
                  icon: _probando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: Text(l10n.probarConexion),
                ),
              ),
              const SizedBox(width: AppNumbers.paddingMedio),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _activa ? _guardarClave : null,
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
