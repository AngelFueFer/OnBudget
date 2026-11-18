import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_gastos_fijos.dart';
import 'package:presupuesto_familiar/main.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_categorias.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_conexion_bancos.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_mercados.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_tarjetas.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_temas.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

class PantallaConfiguracion extends StatefulWidget {
  const PantallaConfiguracion({super.key});

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  final _nominaController = TextEditingController();
  final _diaCobroController = TextEditingController(); // Inyectamos el controlador del día
  final _gastoMensualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  Future<void> _cargarConfiguracion() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nominaController.text = (prefs.getDouble(DBKeys.nominaMensual) ?? 0.0).toStringAsFixed(2);
      _diaCobroController.text = (prefs.getInt(DBKeys.diaCobro) ?? 1).toString(); // Cargamos el día (por defecto el 1)
      _gastoMensualController.text = (prefs.getDouble(DBKeys.gastoMensual) ?? 0.0).toStringAsFixed(2);
    });
  }

  Future<void> _guardarDatosFinancieros() async {
    final prefs = await SharedPreferences.getInstance();

    final nomina = double.tryParse(_nominaController.text.replaceAll(',', '.')) ?? 0.0;
    final gasto = double.tryParse(_gastoMensualController.text.replaceAll(',', '.')) ?? 0.0;

    // Leemos el día y aplicamos la restricción lógica de 1 a 31
    int diaCobro = int.tryParse(_diaCobroController.text) ?? 1;
    if (diaCobro < 1) diaCobro = 1;
    if (diaCobro > 31) diaCobro = 31;

    await prefs.setDouble(DBKeys.nominaMensual, nomina);
    await prefs.setDouble(DBKeys.gastoMensual, gasto);
    await prefs.setInt(DBKeys.diaCobro, diaCobro); // Guardamos la fecha

    if (mounted) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).configuracionGuardada)));
    }
  }

  @override
  void dispose() {
    _nominaController.dispose();
    _diaCobroController.dispose();
    _gastoMensualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.configuracion)),
      body: ListView(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        children: [
          // Temas: modo claro/oscuro y color de acento juntos
          ListTile(
            leading: Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.temas),
            subtitle: Text(l10n.temasDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaTemas()));
            },
          ),
          ListTile(
            leading: Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.idioma),
            trailing: DropdownButton<String>(
              value: localeNotifier.value.languageCode,
              underline: const SizedBox(),
              items: AppStrings.idiomasDisponibles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (codigo) {
                if (codigo != null) cambiarIdioma(codigo);
              },
            ),
          ),
          ListTile(
            leading: Icon(Icons.currency_exchange, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.moneda),
            subtitle: Text(l10n.monedaAviso),
            trailing: DropdownButton<String>(
              value: moneda.codigo,
              underline: const SizedBox(),
              items: Moneda.disponibles.map((m) => DropdownMenuItem(value: m.codigo, child: Text('${m.simbolo}  ${m.codigo}'))).toList(),
              onChanged: (codigo) {
                if (codigo != null) cambiarMoneda(codigo);
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.cloud_sync, color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: Text(l10n.conexionMercados),
            subtitle: Text(l10n.conexionMercadosDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaMercados()));
            },
          ),
          ListTile(
            leading: Icon(Icons.sync_alt, color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: Text(l10n.conexionBancos),
            subtitle: Text(l10n.conexionBancosDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaConexionBancos()));
            },
          ),
          ListTile(
            leading: Icon(Icons.account_balance, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.cuentasBancarias),
            subtitle: Text(l10n.cuentasBancariasDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaCuentasAhorro(todas: true)));
            },
          ),
          ListTile(
            leading: Icon(Icons.credit_card, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.misTarjetas),
            subtitle: Text(l10n.misTarjetasDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaTarjetas()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune, color: AppColors.info),
            title: Text(l10n.configuracionAvanzada),
            subtitle: Text(l10n.configuracionAvanzadaDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaGastosFijos()));
            },
          ),
          ListTile(
            leading: Icon(Icons.category, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.categoriasPersonalizadas),
            subtitle: Text(l10n.categoriasPersonalizadasDescripcion),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaCategorias()));
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppNumbers.paddingCorto),
            child: Text(
              l10n.parametrosMensuales,
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          TextField(
            controller: _nominaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.nominaIngresoBase, prefixIcon: const Icon(Icons.account_balance), suffixText: moneda.simbolo),
          ),
          const SizedBox(height: AppNumbers.paddingMedio),
          // Nuevo TextField para el día de cobro
          TextField(
            controller: _diaCobroController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.diaCobroNomina, prefixIcon: const Icon(Icons.calendar_today)),
          ),
          const SizedBox(height: AppNumbers.paddingMedio),
          TextField(
            controller: _gastoMensualController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.gastoMensualEstimado,
              prefixIcon: const Icon(Icons.shopping_cart),
              suffixText: moneda.simbolo,
            ),
          ),
          const SizedBox(height: AppNumbers.paddingStandard),
          ElevatedButton.icon(onPressed: _guardarDatosFinancieros, icon: const Icon(Icons.save), label: Text(l10n.guardarMetas)),
          const Divider(),
          // La lectura de notificaciones vive en Mis tarjetas (importación desde wallets)
          ListTile(
            leading: Icon(Icons.notifications_active, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.importarTarjetas),
            subtitle: Text(l10n.lecturaNotificaciones),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaTarjetas()));
            },
          ),
        ],
      ),
    );
  }
}
