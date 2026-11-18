import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_tarjetas.dart';
import 'package:presupuesto_familiar/pantallas/visor_tiquet.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/servicio_tiquets.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

class FormularioTransaccion extends StatefulWidget {
  final Transaccion? transaccionAEditar;
  final String? categoriaPredefinida;
  final bool esIngreso; // Lo decide el botón + / − de la pantalla principal
  final String? cuentaPredefinida;
  final String? metodoPagoPredefinido; // Desde las vistas Efectivo / Tarjeta del presupuesto
  final String? cuentaAhorroPredefinida; // Cuenta bancaria de ahorro visible al pulsar + / −

  const FormularioTransaccion({
    super.key,
    this.transaccionAEditar,
    this.categoriaPredefinida,
    this.esIngreso = false,
    this.cuentaPredefinida,
    this.metodoPagoPredefinido,
    this.cuentaAhorroPredefinida,
  });

  @override
  State<FormularioTransaccion> createState() => _FormularioTransaccionState();
}

class _FormularioTransaccionState extends State<FormularioTransaccion> {
  final _conceptoController = TextEditingController();
  final _montoController = TextEditingController();

  late final bool _esIngreso = widget.transaccionAEditar?.esIngreso ?? widget.esIngreso;

  List<String> _categorias = [];
  String? _categoriaSeleccionada;

  final List<String> _cuentas = [AppStrings.cuentaMensual, AppStrings.ahorro];
  String _cuentaSeleccionada = AppStrings.cuentaMensual;

  // Cuenta bancaria de ahorro (solo si la cuenta es Ahorro y hay cuentas creadas)
  List<CuentaAhorro> _cuentasAhorro = [];
  String? _cuentaAhorroSeleccionada;

  // Método de pago (solo para gastos)
  List<String> _tarjetas = [];
  String? _metodoPago;
  String? _tarjetaSeleccionada;

  // Foto del tiquet (solo para gastos)
  late final String? _tiquetOriginal = widget.transaccionAEditar?.tiquet;
  late String? _tiquet = _tiquetOriginal;
  File? _archivoTiquet;
  bool _guardado = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _cargarArchivoTiquet();
  }

  @override
  void dispose() {
    // Si se sale sin guardar, se borra la foto nueva para no dejar archivos huérfanos
    if (!_guardado && _tiquet != _tiquetOriginal) ServicioTiquets.borrar(_tiquet);
    _conceptoController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _cargarArchivoTiquet() async {
    final archivo = await ServicioTiquets.archivo(_tiquet);
    if (mounted) setState(() => _archivoTiquet = archivo);
  }

  Future<void> _anadirTiquet(Future<String?> Function() obtener) async {
    final nuevo = await obtener();
    if (nuevo == null || !mounted) return;
    // Una foto nueva que sustituye a otra aún sin guardar se borra ya
    if (_tiquet != _tiquetOriginal) await ServicioTiquets.borrar(_tiquet);
    _tiquet = nuevo;
    await _cargarArchivoTiquet();
  }

  // Cámara o galería para sustituir la foto actual
  Future<void> _elegirOrigenTiquet(AppLocalizations l10n) async {
    final obtener = await showModalBottomSheet<Future<String?> Function()>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.hacerFotoTiquet),
              onTap: () => Navigator.pop(context, ServicioTiquets.hacerFoto),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.tiquetDesdeGaleria),
              onTap: () => Navigator.pop(context, ServicioTiquets.elegirDeGaleria),
            ),
          ],
        ),
      ),
    );
    if (obtener != null) await _anadirTiquet(obtener);
  }

  Future<void> _quitarTiquet() async {
    if (_tiquet != _tiquetOriginal) await ServicioTiquets.borrar(_tiquet);
    setState(() {
      _tiquet = null;
      _archivoTiquet = null;
    });
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonGuardado = prefs.getString(DBKeys.categoriasJson);

    // Si la memoria está vacía, inyectamos las categorías por defecto
    if (jsonGuardado == null) {
      jsonGuardado = jsonEncode(AppStrings.categoriasConIconoDefecto);
      await prefs.setString(DBKeys.categoriasJson, jsonGuardado);
    }

    final List<dynamic> decodificado = jsonDecode(jsonGuardado);
    List<String> listaNombres = decodificado.map((e) => e['nombre'].toString()).toList();
    // Al editar, conserva la categoría original aunque no esté en la lista (ej. Remanente o una borrada)
    final categoriaEditada = widget.transaccionAEditar?.categoria;
    if (categoriaEditada != null && !listaNombres.contains(categoriaEditada)) listaNombres.add(categoriaEditada);

    final tarjetas = await ServicioTarjetas.cargar();
    final cuentasAhorro = await ServicioCuentasAhorro.cargar();
    if (!mounted) return;

    // Ordenar alfabéticamente (A-Z) según el nombre visible en el idioma actual
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);
    listaNombres.sort((a, b) => l10n.nombreCategoria(a).toLowerCase().compareTo(l10n.nombreCategoria(b).toLowerCase()));

    setState(() {
      _categorias = listaNombres;
      _tarjetas = tarjetas;
      _cuentasAhorro = cuentasAhorro;
      final principal = cuentasAhorro.where((c) => c.principal).firstOrNull ?? cuentasAhorro.firstOrNull;
      final preferida = widget.transaccionAEditar?.cuentaAhorro ?? widget.cuentaAhorroPredefinida;
      _cuentaAhorroSeleccionada = cuentasAhorro.any((c) => c.id == preferida) ? preferida : principal?.id;
      final editar = widget.transaccionAEditar;

      if (editar != null) {
        _conceptoController.text = editar.concepto;
        _montoController.text = (editar.montoEnCentimos / AppNumbers.centimosEnEuro).toStringAsFixed(moneda.decimales);
        _categoriaSeleccionada = editar.categoria;
        if (_cuentas.contains(editar.tarroDestino)) _cuentaSeleccionada = editar.tarroDestino;

        _metodoPago = editar.metodoPago;
        _tarjetaSeleccionada = editar.tarjeta;
        // Si la tarjeta se borró después, se sigue mostrando en este movimiento
        if (_tarjetaSeleccionada != null && !_tarjetas.contains(_tarjetaSeleccionada)) _tarjetas.add(_tarjetaSeleccionada!);
      } else {
        if (_cuentas.contains(widget.cuentaPredefinida)) _cuentaSeleccionada = widget.cuentaPredefinida!;
        _categoriaSeleccionada = widget.categoriaPredefinida != null && _categorias.contains(widget.categoriaPredefinida)
            ? widget.categoriaPredefinida
            : _categorias.first;

        // Método indicado por la vista (Efectivo / Tarjeta) o, si no, el último usado
        final ultimaTarjeta = prefs.getString(DBKeys.ultimaTarjeta);
        final preferido = widget.metodoPagoPredefinido ?? prefs.getString(DBKeys.ultimoMetodoPago);
        if (preferido == AppStrings.metodoTarjeta) {
          // Sin tarjetas guardadas queda sin marcar (cuenta como pago con tarjeta en el presupuesto)
          if (_tarjetas.isNotEmpty) {
            _metodoPago = AppStrings.metodoTarjeta;
            _tarjetaSeleccionada = _tarjetas.contains(ultimaTarjeta) ? ultimaTarjeta : _tarjetas.first;
          }
        } else {
          _metodoPago = AppStrings.metodoEfectivo;
        }
      }
    });
  }

  void _seleccionarEfectivo() {
    setState(() {
      _metodoPago = AppStrings.metodoEfectivo;
      _tarjetaSeleccionada = null;
    });
  }

  void _seleccionarTarjeta(String tarjeta) {
    setState(() {
      _metodoPago = AppStrings.metodoTarjeta;
      _tarjetaSeleccionada = tarjeta;
    });
  }

  Future<void> _anadirTarjeta() async {
    final nueva = await mostrarDialogoNuevaTarjeta(context);
    if (nueva == null || !mounted) return;
    setState(() => _tarjetas.add(nueva));
    _seleccionarTarjeta(nueva);
  }

  Future<void> _guardar() async {
    final concepto = _conceptoController.text.trim();
    final monto = double.tryParse(_montoController.text.replaceAll(',', '.'));
    if (concepto.isEmpty || monto == null || monto <= 0) return;

    final nuevaTransaccion = Transaccion(
      id: widget.transaccionAEditar?.id,
      montoEnCentimos: (monto * AppNumbers.centimosEnEuro).round(),
      concepto: concepto,
      fecha: widget.transaccionAEditar?.fecha ?? DateTime.now(),
      categoria: _categoriaSeleccionada ?? AppStrings.categoriaGeneral,
      esIngreso: _esIngreso,
      tarroDestino: _cuentaSeleccionada,
      metodoPago: _esIngreso ? null : _metodoPago,
      tarjeta: _esIngreso ? null : _tarjetaSeleccionada,
      cuentaAhorro: _cuentaSeleccionada == AppStrings.ahorro ? _cuentaAhorroSeleccionada : null,
      tiquet: _esIngreso ? null : _tiquet,
    );

    final db = DBHelper();
    if (widget.transaccionAEditar == null) {
      await db.insertarTransaccion(nuevaTransaccion);
    } else {
      await db.actualizarTransaccion(nuevaTransaccion);
    }
    _guardado = true;
    // La foto anterior ya no la usa ningún movimiento
    if (_tiquetOriginal != nuevaTransaccion.tiquet) await ServicioTiquets.borrar(_tiquetOriginal);
    if (_esIngreso && _tiquet != _tiquetOriginal) await ServicioTiquets.borrar(_tiquet);

    if (!_esIngreso && _metodoPago != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DBKeys.ultimoMetodoPago, _metodoPago!);
      if (_tarjetaSeleccionada != null) await prefs.setString(DBKeys.ultimaTarjeta, _tarjetaSeleccionada!);
    }

    if (mounted) Navigator.pop(context);
  }

  Widget _construirSelectorMetodoPago(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.metodoPago, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppNumbers.paddingCorto),
        Wrap(
          spacing: AppNumbers.paddingCorto,
          runSpacing: AppNumbers.paddingCorto,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.payments, size: 18),
              label: Text(l10n.efectivo),
              selected: _metodoPago == AppStrings.metodoEfectivo,
              onSelected: (_) => _seleccionarEfectivo(),
            ),
            ..._tarjetas.map(
              (tarjeta) => ChoiceChip(
                avatar: const Icon(Icons.credit_card, size: 18),
                label: Text(tarjeta),
                selected: _metodoPago == AppStrings.metodoTarjeta && _tarjetaSeleccionada == tarjeta,
                onSelected: (_) => _seleccionarTarjeta(tarjeta),
              ),
            ),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(l10n.anadirTarjeta), onPressed: _anadirTarjeta),
          ],
        ),
      ],
    );
  }

  Widget _construirTiquet(AppLocalizations l10n) {
    final botonesAnadir = [
      OutlinedButton.icon(
        icon: const Icon(Icons.photo_camera),
        label: Text(l10n.hacerFotoTiquet),
        onPressed: () => _anadirTiquet(ServicioTiquets.hacerFoto),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.photo_library),
        label: Text(l10n.tiquetDesdeGaleria),
        onPressed: () => _anadirTiquet(ServicioTiquets.elegirDeGaleria),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.tiquet, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppNumbers.paddingCorto),
        if (_archivoTiquet == null)
          Wrap(spacing: AppNumbers.paddingCorto, runSpacing: AppNumbers.paddingCorto, children: botonesAnadir)
        else
          Row(
            children: [
              GestureDetector(
                onTap: () => abrirTiquet(context, _tiquet!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_archivoTiquet!, width: 80, height: 100, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: AppNumbers.paddingStandard),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(l10n.cambiarTiquet),
                      onPressed: () => _elegirOrigenTiquet(l10n),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      label: Text(l10n.quitarTiquet, style: const TextStyle(color: AppColors.error)),
                      onPressed: _quitarTiquet,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_categorias.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.transaccionAEditar == null
              ? (_esIngreso ? l10n.nuevoIngreso : l10n.nuevoGasto)
              : (_esIngreso ? l10n.editarIngreso : l10n.editarGasto),
        ),
        backgroundColor: (_esIngreso ? AppColors.saldoPositivo : AppColors.saldoNegativo).withValues(alpha: AppNumbers.opacityMedia),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _cuentaSeleccionada,
              decoration: InputDecoration(labelText: l10n.cuentaAfectada),
              items: _cuentas.map((String cuenta) => DropdownMenuItem(value: cuenta, child: Text(l10n.nombreCuenta(cuenta)))).toList(),
              onChanged: (String? nuevoValor) {
                if (nuevoValor != null) setState(() => _cuentaSeleccionada = nuevoValor);
              },
            ),
            if (_cuentaSeleccionada == AppStrings.ahorro && _cuentasAhorro.isNotEmpty) ...[
              const SizedBox(height: AppNumbers.paddingStandard),
              DropdownButtonFormField<String>(
                initialValue: _cuentaAhorroSeleccionada,
                decoration: InputDecoration(labelText: l10n.cuentaAhorroCampo, prefixIcon: const Icon(Icons.savings)),
                items: _cuentasAhorro
                    .map(
                      (cuenta) => DropdownMenuItem(
                        value: cuenta.id,
                        child: Text(cuenta.principal ? '${cuenta.nombreCompleto} ★' : cuenta.nombreCompleto, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (String? id) {
                  if (id != null) setState(() => _cuentaAhorroSeleccionada = id);
                },
              ),
            ],
            const SizedBox(height: AppNumbers.paddingStandard),
            TextField(
              controller: _conceptoController,
              decoration: InputDecoration(labelText: l10n.etiquetaConcepto),
            ),
            const SizedBox(height: AppNumbers.paddingStandard),
            DropdownButtonFormField<String>(
              initialValue: _categoriaSeleccionada,
              decoration: InputDecoration(labelText: l10n.categoria),
              items: _categorias.map((String categoria) => DropdownMenuItem(value: categoria, child: Text(l10n.nombreCategoria(categoria)))).toList(),
              onChanged: (String? nuevoValor) {
                if (nuevoValor != null) setState(() => _categoriaSeleccionada = nuevoValor);
              },
            ),
            const SizedBox(height: AppNumbers.paddingStandard),
            TextField(
              controller: _montoController,
              decoration: InputDecoration(labelText: l10n.importe, suffixText: moneda.simbolo),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (!_esIngreso) ...[
              const SizedBox(height: AppNumbers.paddingLargo),
              Align(alignment: Alignment.centerLeft, child: _construirSelectorMetodoPago(l10n)),
              const SizedBox(height: AppNumbers.paddingLargo),
              Align(alignment: Alignment.centerLeft, child: _construirTiquet(l10n)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(onPressed: _guardar, child: Text(l10n.guardar)),
          ],
        ),
      ),
    );
  }
}
