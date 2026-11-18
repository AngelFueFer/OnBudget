import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_principal.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_tarjetas.dart';
import 'package:presupuesto_familiar/main.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';
import 'package:presupuesto_familiar/utilidades/url_servidor.dart';

class PantallaOnboarding extends StatefulWidget {
  const PantallaOnboarding({super.key});

  @override
  State<PantallaOnboarding> createState() => _PantallaOnboardingState();
}

class _PantallaOnboardingState extends State<PantallaOnboarding> {
  final PageController _pageController = PageController();
  int _paginaActual = 0;
  static const int _numeroPasos = 5;
  // Orden: idioma y apariencia, dónde guardar los datos, finanzas, gastos fijos y tarjetas al final
  static const int _pasoAlmacenamiento = 1;

  // --- VARIABLES PASO 2: Dónde guardar los datos ---
  String _modoAlmacenamiento = AppStrings.almacenamientoLocal;
  final _urlServidorController = TextEditingController();
  bool _urlServidorInvalida = false;

  // --- VARIABLES PASO 1: Apariencia e Idioma ---
  bool _esModoOscuro = themeNotifier.value == ThemeMode.dark;
  String _idiomaSeleccionado = localeNotifier.value.languageCode;

  // --- VARIABLES PASO 3: Financiera ---
  final _nominaController = TextEditingController();
  final _gastoController = TextEditingController();
  final _diaCobroController = TextEditingController(text: '1');

  // --- VARIABLES PASO 4: Gastos Fijos ---
  final List<Map<String, dynamic>> _gastosFijos = [];

  @override
  void dispose() {
    _pageController.dispose();
    _urlServidorController.dispose();
    _nominaController.dispose();
    _gastoController.dispose();
    _diaCobroController.dispose();
    super.dispose();
  }

  Future<void> _finalizarConfiguracion() async {
    final nomina = double.tryParse(_nominaController.text.replaceAll(',', '.')) ?? 0.0;
    final gasto = double.tryParse(_gastoController.text.replaceAll(',', '.')) ?? 0.0;

    int diaCobro = int.tryParse(_diaCobroController.text) ?? 1;
    if (diaCobro < 1) diaCobro = 1;
    if (diaCobro > 31) diaCobro = 31;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(DBKeys.idioma, _idiomaSeleccionado);
    await prefs.setDouble(DBKeys.nominaMensual, nomina);
    await prefs.setDouble(DBKeys.gastoMensual, gasto);
    await prefs.setInt(DBKeys.diaCobro, diaCobro);
    await prefs.setString(DBKeys.gastosFijos, jsonEncode(_gastosFijos));
    await prefs.setString(DBKeys.modoAlmacenamiento, _modoAlmacenamiento);
    // La URL solo se guarda si se eligió servidor propio (ya validada al salir del primer paso)
    final url = UrlServidor.normalizar(_urlServidorController.text);
    if (_modoAlmacenamiento == AppStrings.almacenamientoServidor && url != null) {
      await prefs.setString(DBKeys.urlServidor, url);
    } else {
      await prefs.remove(DBKeys.urlServidor);
    }
    await prefs.setBool(DBKeys.esPrimeraVez, false);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PantallaPrincipal()),
      );
    }
  }

  void _avanzarPagina() {
    // Con servidor propio hace falta una dirección válida para seguir
    if (_paginaActual == _pasoAlmacenamiento && _modoAlmacenamiento == AppStrings.almacenamientoServidor) {
      final invalida = UrlServidor.normalizar(_urlServidorController.text) == null;
      setState(() => _urlServidorInvalida = invalida);
      if (invalida) return;
    }
    FocusScope.of(context).unfocus();
    if (_paginaActual < _numeroPasos - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finalizarConfiguracion();
    }
  }

  void _retrocederPagina() {
    if (_paginaActual > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _mostrarDialogoNuevoGasto() {
    final nombreController = TextEditingController();
    final montoController = TextEditingController();
    String categoriaSeleccionada = AppStrings.categoriaHogar;

    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(l10n.anadirGastoFijo),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreController,
                    decoration: InputDecoration(labelText: l10n.etiquetaConcepto),
                  ),
                  const SizedBox(height: AppNumbers.paddingCorto),
                  DropdownButtonFormField<String>(
                    initialValue: categoriaSeleccionada,
                    decoration: InputDecoration(labelText: l10n.categoria),
                    items: AppStrings.categoriasGastosFijos
                        .map((c) => DropdownMenuItem(value: c, child: Text(l10n.nombreCategoria(c))))
                        .toList(),
                    onChanged: (val) => setStateDialog(() => categoriaSeleccionada = val!),
                  ),
                  const SizedBox(height: AppNumbers.paddingCorto),
                  TextField(
                    controller: montoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: l10n.importe, suffixText: Moneda.of(context).simbolo),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancelar),
                ),
                ElevatedButton(
                  onPressed: () {
                    final monto = double.tryParse(montoController.text.replaceAll(',', '.')) ?? 0.0;
                    if (nombreController.text.isNotEmpty && monto > 0) {
                      setState(() {
                        _gastosFijos.add({
                          'nombre': nombreController.text,
                          'categoria': categoriaSeleccionada,
                          'monto': monto,
                        });
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: Text(l10n.anadir),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingLargo, vertical: AppNumbers.paddingStandard),
              child: Row(
                children: List.generate(_numeroPasos, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      decoration: BoxDecoration(
                        color: _paginaActual >= index ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _paginaActual = index);
                },
                children: [
                  _construirPasoApariencia(),
                  _construirPasoAlmacenamiento(),
                  _construirPasoFinanciero(),
                  _construirPasoGastosFijos(),
                  _construirPasoTarjetas(), // Tarjetas + lectura de notificaciones (sin conexión con el banco)
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppNumbers.paddingLargo),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_paginaActual > 0)
                    TextButton(
                      onPressed: _retrocederPagina,
                      child: Text(l10n.atras, style: TextStyle(fontSize: AppNumbers.fontSizeSubtitulo, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  else
                    const SizedBox(width: 64),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: AppNumbers.paddingStandard),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: _avanzarPagina,
                    child: Text(
                      _paginaActual == _numeroPasos - 1 ? l10n.finalizar : l10n.siguiente,
                      style: const TextStyle(fontSize: AppNumbers.fontSizeTituloSeccion, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- VISTAS DE CADA PASO ---

  // Elección entre guardar solo en local o en un servidor propio
  Widget _construirPasoAlmacenamiento() {
    final l10n = AppLocalizations.of(context);
    final esquema = Theme.of(context).colorScheme;
    final conServidor = _modoAlmacenamiento == AppStrings.almacenamientoServidor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppNumbers.paddingLargo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.dns, size: 80, color: esquema.primary),
          const SizedBox(height: AppNumbers.paddingLargo),
          Text(l10n.dondeGuardarDatos, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppNumbers.fontSizeTitulo, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppNumbers.paddingCorto),
          Text(l10n.dondeGuardarDescripcion, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          RadioGroup<String>(
            groupValue: _modoAlmacenamiento,
            onChanged: (String? modo) {
              if (modo == null) return;
              setState(() {
                _modoAlmacenamiento = modo;
                _urlServidorInvalida = false;
              });
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  value: AppStrings.almacenamientoLocal,
                  title: Text(l10n.soloEsteDispositivo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(l10n.soloEsteDispositivoDescripcion),
                  secondary: Icon(Icons.phone_android, color: esquema.primary),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: AppStrings.almacenamientoServidor,
                  title: Text(l10n.servidorPropio, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(l10n.servidorPropioDescripcion),
                  secondary: Icon(Icons.dns, color: esquema.primary),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (conServidor) ...[
            const SizedBox(height: AppNumbers.paddingStandard),
            TextField(
              controller: _urlServidorController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.urlServidor,
                hintText: 'https://',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                errorText: _urlServidorInvalida ? l10n.urlServidorInvalida : null,
              ),
              onChanged: (_) {
                if (_urlServidorInvalida) setState(() => _urlServidorInvalida = false);
              },
            ),
            const SizedBox(height: AppNumbers.paddingMedio),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: AppNumbers.paddingCorto),
                Expanded(child: Text(l10n.sincronizacionEnDesarrollo, style: TextStyle(fontSize: AppNumbers.fontSizeAyuda, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirPasoApariencia() {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppNumbers.paddingLargo),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // Primer paso: bienvenida con el logo; el idioma va primero para entender el resto
          Center(child: Image.asset('assets/branding/logo.png', width: 96, height: 96)),
          const SizedBox(height: AppNumbers.paddingLargo),
          Text(l10n.aparienciaEIdioma, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppNumbers.fontSizeTitulo, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),

          // Selector de Tema
          Material(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              title: Text(l10n.modoOscuro, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(l10n.paletaColores),
              value: _esModoOscuro,
              activeThumbColor: Theme.of(context).colorScheme.primary,
              secondary: Icon(Icons.dark_mode, color: Theme.of(context).colorScheme.primary),
              onChanged: (valor) async {
                setState(() => _esModoOscuro = valor);
                await cambiarModoOscuro(valor); // Dispara el cambio al instante
              },
            ),
          ),

          const SizedBox(height: AppNumbers.paddingLargo),
          Padding(
            padding: const EdgeInsets.only(left: AppNumbers.paddingCorto, bottom: AppNumbers.paddingCorto),
            child: Text(l10n.idiomaApp, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ),

          // Selector de Idiomas: el cambio se aplica al instante en toda la app
          RadioGroup<String>(
            groupValue: _idiomaSeleccionado,
            onChanged: (String? codigo) {
              if (codigo == null) return;
              setState(() => _idiomaSeleccionado = codigo);
              cambiarIdioma(codigo);
            },
            child: Column(
              children: AppStrings.idiomasDisponibles.entries.map((idioma) {
                return RadioListTile<String>(
                  title: Text(idioma.value),
                  value: idioma.key,
                  activeColor: Theme.of(context).colorScheme.primary,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPasoFinanciero() {
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppNumbers.paddingLargo),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.account_balance, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppNumbers.paddingLargo),
          Text(l10n.tusDatosFinancieros, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppNumbers.fontSizeTitulo, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppNumbers.paddingCorto),
          Text(l10n.datosFinancierosDescripcion, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          DropdownButtonFormField<String>(
            initialValue: moneda.codigo,
            decoration: InputDecoration(labelText: l10n.moneda, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.currency_exchange)),
            items: Moneda.disponibles
                .map((m) => DropdownMenuItem(value: m.codigo, child: Text('${m.simbolo}  ${l10n.nombreMoneda(m.codigo)}')))
                .toList(),
            onChanged: (codigo) {
              if (codigo != null) cambiarMoneda(codigo);
            },
          ),
          const SizedBox(height: AppNumbers.paddingStandard),
          TextField(
            controller: _nominaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.nominaMensual, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.payments), suffixText: moneda.simbolo),
          ),
          const SizedBox(height: AppNumbers.paddingStandard),
          TextField(
            controller: _gastoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.presupuestoEstimado, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.shopping_cart), suffixText: moneda.simbolo),
          ),
          const SizedBox(height: AppNumbers.paddingStandard),
          TextField(
            controller: _diaCobroController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.diaCobro, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.calendar_today)),
          ),
        ],
      ),
    );
  }

  // Tarjetas: alta manual + importación desde wallets (lectura de notificaciones)
  Widget _construirPasoTarjetas() {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppNumbers.paddingLargo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.credit_card, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppNumbers.paddingStandard),
          Text(l10n.importarTarjetas, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppNumbers.fontSizeTitulo, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppNumbers.paddingCorto),
          Text(l10n.tarjetasOnboardingDescripcion, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppNumbers.paddingLargo),
          const PanelTarjetas(),
        ],
      ),
    );
  }

  Widget _construirPasoGastosFijos() {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppNumbers.paddingLargo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppNumbers.paddingStandard),
          Text(l10n.gastosFijos, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppNumbers.fontSizeTitulo, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppNumbers.paddingCorto),
          Text(l10n.gastosFijosDescripcion, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppNumbers.paddingStandard),
          ElevatedButton.icon(
            onPressed: _mostrarDialogoNuevoGasto,
            icon: const Icon(Icons.add),
            label: Text(l10n.anadirGastoFijo),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer, foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: AppNumbers.paddingStandard),
          Expanded(
            child: _gastosFijos.isEmpty
                ? Center(child: Text(l10n.ningunGastoFijo, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                : ListView.builder(
                    itemCount: _gastosFijos.length,
                    itemBuilder: (context, index) {
                      final gasto = _gastosFijos[index];
                      return Card(
                        child: ListTile(
                          title: Text(gasto['nombre']),
                          subtitle: Text(l10n.nombreCategoria(gasto['categoria'])),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(Moneda.of(context).formatear(-(gasto['monto'] as num).toDouble()), style: const TextStyle(color: AppColors.saldoNegativo, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                tooltip: AppLocalizations.of(context).borrar,
                                onPressed: () => setState(() => _gastosFijos.removeAt(index)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}