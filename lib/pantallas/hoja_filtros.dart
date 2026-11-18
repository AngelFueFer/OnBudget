import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/filtro_movimientos.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

// Abre la hoja de filtros. Devuelve el filtro aplicado, o null si se cierra sin aplicar.
Future<FiltroMovimientos?> mostrarHojaFiltros(
  BuildContext context, {
  required FiltroMovimientos filtroActual,
  required List<String> categoriasDisponibles,
  String Function(String)? nombreCategoria, // Por defecto, el nombre traducido de la categoría
  String? tituloCategorias,
  bool conFechas = true,
}) {
  return showModalBottomSheet<FiltroMovimientos>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _HojaFiltros(
      filtroInicial: filtroActual,
      categorias: categoriasDisponibles,
      nombreCategoria: nombreCategoria,
      tituloCategorias: tituloCategorias,
      conFechas: conFechas,
    ),
  );
}

// "01/10/2026 – 15/10/2026" según el idioma
String formatearRangoFechas(BuildContext context, DateTimeRange rango) {
  final formato = MaterialLocalizations.of(context);
  return '${formato.formatShortDate(rango.start)} – ${formato.formatShortDate(rango.end)}';
}

class _HojaFiltros extends StatefulWidget {
  final FiltroMovimientos filtroInicial;
  final List<String> categorias;
  final String Function(String)? nombreCategoria;
  final String? tituloCategorias;
  final bool conFechas;

  const _HojaFiltros({required this.filtroInicial, required this.categorias, this.nombreCategoria, this.tituloCategorias, this.conFechas = true});

  @override
  State<_HojaFiltros> createState() => _HojaFiltrosState();
}

class _HojaFiltrosState extends State<_HojaFiltros> {
  late Set<String> _categorias = {...widget.filtroInicial.categorias};
  late DateTimeRange? _fechas = widget.filtroInicial.fechas;
  late final TextEditingController _minimo = TextEditingController(text: _texto(widget.filtroInicial.importeMinimo));
  late final TextEditingController _maximo = TextEditingController(text: _texto(widget.filtroInicial.importeMaximo));

  static String _texto(double? valor) => valor == null ? '' : valor.toString();
  static double? _leer(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _minimo.dispose();
    _maximo.dispose();
    super.dispose();
  }

  void _limpiar() {
    setState(() {
      _categorias = {};
      _fechas = null;
      _minimo.clear();
      _maximo.clear();
    });
  }

  Future<void> _elegirFechas() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(ahora.year + 1, 12, 31), initialDateRange: _fechas);
    if (rango != null) setState(() => _fechas = rango);
  }

  void _aplicar() {
    var minimo = _leer(_minimo.text);
    var maximo = _leer(_maximo.text);
    // Si se escriben al revés, se intercambian
    if (minimo != null && maximo != null && minimo > maximo) {
      final aux = minimo;
      minimo = maximo;
      maximo = aux;
    }
    Navigator.pop(context, FiltroMovimientos(categorias: _categorias, importeMinimo: minimo, importeMaximo: maximo, fechas: _fechas));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);
    final estiloSeccion = Theme.of(context).textTheme.titleSmall;

    return Padding(
      // Deja sitio al teclado al escribir los importes
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppNumbers.paddingLargo, 0, AppNumbers.paddingLargo, AppNumbers.paddingLargo),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.filtrar, style: Theme.of(context).textTheme.titleLarge)),
                TextButton(onPressed: _limpiar, child: Text(l10n.limpiar)),
              ],
            ),
            const SizedBox(height: AppNumbers.paddingStandard),

            Text(widget.tituloCategorias ?? l10n.categorias, style: estiloSeccion),
            const SizedBox(height: AppNumbers.paddingCorto),
            Wrap(
              spacing: AppNumbers.paddingCorto,
              runSpacing: AppNumbers.paddingCorto,
              children: widget.categorias.map((categoria) {
                return FilterChip(
                  label: Text((widget.nombreCategoria ?? l10n.nombreCategoria)(categoria)),
                  selected: _categorias.contains(categoria),
                  onSelected: (seleccionada) => setState(() {
                    seleccionada ? _categorias.add(categoria) : _categorias.remove(categoria);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: AppNumbers.paddingLargo),

            Text(l10n.importe, style: estiloSeccion),
            const SizedBox(height: AppNumbers.paddingCorto),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minimo,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: l10n.importeMinimo, suffixText: moneda.simbolo, border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: AppNumbers.paddingMedio),
                Expanded(
                  child: TextField(
                    controller: _maximo,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: l10n.importeMaximo, suffixText: moneda.simbolo, border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppNumbers.paddingLargo),

            if (widget.conFechas) ...[
              Text(l10n.fechas, style: estiloSeccion),
              const SizedBox(height: AppNumbers.paddingCorto),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _elegirFechas,
                      icon: const Icon(Icons.date_range),
                      label: Text(_fechas == null ? l10n.elegirFechas : formatearRangoFechas(context, _fechas!)),
                    ),
                  ),
                  if (_fechas != null) IconButton(tooltip: l10n.limpiar, icon: const Icon(Icons.close), onPressed: () => setState(() => _fechas = null)),
                ],
              ),
              const SizedBox(height: AppNumbers.paddingLargo),
            ],

            FilledButton.icon(onPressed: _aplicar, icon: const Icon(Icons.filter_list), label: Text(l10n.aplicar)),
          ],
        ),
      ),
    );
  }
}
