import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/activo.dart';
import 'package:presupuesto_familiar/servicios/api_bolsa.dart';
import 'package:presupuesto_familiar/utilidades/diccionario_iconos.dart';
import 'package:presupuesto_familiar/utilidades/isin.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

class FormularioInversion extends StatefulWidget {
  final ActivoFinanciero? activoAEditar; // Variable para recibir datos previos
  final ActivoFinanciero? activoBase; // Compra rápida: copia tipo, nombre, ticker e ISIN de un activo
  final double? precioPredefinido;
  final String? tipoPredefinido; // Tipo elegido en el desplegable de Inversión
  final bool esCompra; // Lo decide el botón + / − de la pantalla principal

  const FormularioInversion({super.key, this.activoAEditar, this.activoBase, this.precioPredefinido, this.tipoPredefinido, this.esCompra = true});

  @override
  State<FormularioInversion> createState() => _FormularioInversionState();
}

class _FormularioInversionState extends State<FormularioInversion> {
  final _identificadorController = TextEditingController(); // Ticker o ISIN
  final _nombreController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();

  late final bool _esCompra = widget.activoAEditar != null ? widget.activoAEditar!.cantidad > 0 : widget.esCompra;
  late String _tipo = (widget.activoAEditar ?? widget.activoBase)?.tipoEfectivo ?? widget.tipoPredefinido ?? AppStrings.tipoAccion;
  String? _errorIdentificador;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final origen = widget.activoAEditar ?? widget.activoBase;
    if (origen != null) {
      // Se muestra el ISIN si se dio de alta así; si no, el ticker
      _identificadorController.text = origen.isin ?? origen.ticker;
      _nombreController.text = origen.nombre ?? '';
    }
    if (widget.activoAEditar != null) {
      _cantidadController.text = widget.activoAEditar!.cantidad.abs().toString();
      _precioController.text = widget.activoAEditar!.precioCompra.toString();
    } else if (widget.precioPredefinido != null) {
      _precioController.text = widget.precioPredefinido.toString();
    }
  }

  @override
  void dispose() {
    _identificadorController.dispose();
    _nombreController.dispose();
    _cantidadController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  // Ticker para consultar el precio: si es un ISIN, se busca en la API (o se reutiliza el ya resuelto)
  Future<({String ticker, String? isin})?> _resolverIdentificador(String entrada, AppLocalizations l10n) async {
    if (!Isin.pareceIsin(entrada)) return (ticker: entrada, isin: null);
    if (!Isin.esValido(entrada)) {
      setState(() => _errorIdentificador = l10n.isinNoValido);
      return null;
    }
    final previo = widget.activoAEditar ?? widget.activoBase;
    if (previo != null && previo.isin == entrada && !Isin.pareceIsin(previo.ticker)) {
      return (ticker: previo.ticker, isin: entrada);
    }
    final ticker = await ApiBolsa.buscarTickerPorIsin(entrada);
    return (ticker: ticker ?? entrada, isin: entrada);
  }

  Future<void> _guardar() async {
    final l10n = AppLocalizations.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    final entrada = _identificadorController.text.trim().toUpperCase();
    final cantidad = double.tryParse(_cantidadController.text.replaceAll(',', '.'));
    final precio = double.tryParse(_precioController.text.replaceAll(',', '.'));
    if (entrada.isEmpty || cantidad == null || cantidad <= 0 || precio == null || precio <= 0 || _guardando) return;

    setState(() {
      _guardando = true;
      _errorIdentificador = null;
    });
    final resuelto = await _resolverIdentificador(entrada, l10n);
    if (resuelto == null) {
      if (mounted) setState(() => _guardando = false);
      return;
    }

    final nombre = _nombreController.text.trim();
    final nuevoActivo = ActivoFinanciero(
      id: widget.activoAEditar?.id, // Mantenemos el ID si estamos editando
      ticker: resuelto.ticker,
      cantidad: _esCompra ? cantidad : -cantidad,
      precioCompra: precio,
      tipo: _tipo,
      nombre: nombre.isEmpty ? null : nombre,
      isin: resuelto.isin,
    );

    final db = DBHelper();
    if (widget.activoAEditar == null) {
      await db.insertarActivo(nuevoActivo);
    } else {
      await db.actualizarActivo(nuevoActivo);
    }

    // ISIN sin ticker: se guarda igual, pero sin precio en vivo
    if (resuelto.isin != null && resuelto.ticker == resuelto.isin) {
      mensajero.showSnackBar(SnackBar(content: Text(l10n.isinNoResuelto)));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.activoAEditar == null ? (_esCompra ? l10n.nuevaCompra : l10n.nuevaVenta) : (_esCompra ? l10n.editarCompra : l10n.editarVenta),
        ),
        backgroundColor: (_esCompra ? Theme.of(context).colorScheme.onSurfaceVariant : AppColors.advertencia).withValues(alpha: AppNumbers.opacityMedia),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tipoInversion, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppNumbers.paddingCorto),
            Wrap(
              spacing: AppNumbers.paddingCorto,
              runSpacing: AppNumbers.paddingCorto,
              children: AppStrings.tiposInversion.map((tipo) {
                return ChoiceChip(
                  avatar: Icon(iconosTipoInversion[tipo], size: 18),
                  label: Text(l10n.nombreTipoInversion(tipo)),
                  selected: _tipo == tipo,
                  onSelected: (_) => setState(() => _tipo = tipo),
                );
              }).toList(),
            ),
            const SizedBox(height: AppNumbers.paddingLargo),
            TextField(
              controller: _identificadorController,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                if (_errorIdentificador != null) setState(() => _errorIdentificador = null);
              },
              decoration: InputDecoration(labelText: l10n.tickerOIsin, errorText: _errorIdentificador),
            ),
            const SizedBox(height: AppNumbers.paddingStandard),
            TextField(
              controller: _nombreController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.nombreOpcional),
            ),
            const SizedBox(height: AppNumbers.paddingStandard),
            TextField(
              controller: _cantidadController,
              decoration: InputDecoration(labelText: l10n.cantidadTitulos),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: AppNumbers.paddingStandard),
            TextField(
              controller: _precioController,
              decoration: InputDecoration(labelText: l10n.precioPorTitulo, suffixText: Moneda.of(context).simbolo),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.guardar),
            ),
          ],
        ),
      ),
    );
  }
}
