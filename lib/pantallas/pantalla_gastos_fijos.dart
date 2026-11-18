import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

class PantallaGastosFijos extends StatefulWidget {
  const PantallaGastosFijos({super.key});

  @override
  State<PantallaGastosFijos> createState() => _PantallaGastosFijosState();
}

class _PantallaGastosFijosState extends State<PantallaGastosFijos> {
  List<Map<String, dynamic>> _gastosFijos = [];

  @override
  void initState() {
    super.initState();
    _cargarGastos();
  }

  Future<void> _cargarGastos() async {
    final prefs = await SharedPreferences.getInstance();
    final String datosGuardados = prefs.getString(DBKeys.gastosFijos) ?? '[]';
    final List<dynamic> decodificado = jsonDecode(datosGuardados);

    setState(() {
      _gastosFijos = decodificado.map((e) => e as Map<String, dynamic>).toList();
    });
  }

  Future<void> _guardarGastos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DBKeys.gastosFijos, jsonEncode(_gastosFijos));
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
              title: Text(l10n.nuevoGastoFijo),
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
                      _guardarGastos();
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

  void _eliminarGasto(int index) {
    setState(() {
      _gastosFijos.removeAt(index);
    });
    _guardarGastos();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.configuracionAvanzada)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppNumbers.paddingStandard),
            child: Text(
              l10n.gastosFijosExplicacion,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _gastosFijos.length,
              itemBuilder: (context, index) {
                final gasto = _gastosFijos[index];
                return ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text(gasto['nombre']),
                  subtitle: Text(l10n.nombreCategoria(gasto['categoria'])),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Moneda.of(context).formatear(-(gasto['monto'] as num).toDouble()), style: const TextStyle(color: AppColors.saldoNegativo, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        tooltip: AppLocalizations.of(context).borrar,
                        onPressed: () => _eliminarGasto(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoNuevoGasto,
        icon: const Icon(Icons.add),
        label: Text(l10n.desglosarRecibo),
      ),
    );
  }
}