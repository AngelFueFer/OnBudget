import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/utilidades/diccionario_iconos.dart';

class PantallaCategorias extends StatefulWidget {
  const PantallaCategorias({super.key});

  @override
  State<PantallaCategorias> createState() => _PantallaCategoriasState();
}

class _PantallaCategoriasState extends State<PantallaCategorias> {
  List<Map<String, dynamic>> _categorias = [];

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonGuardado = prefs.getString(DBKeys.categoriasJson);

    if (jsonGuardado == null) {
      _categorias = AppStrings.categoriasConIconoDefecto.map((c) => Map<String, dynamic>.from(c)).toList();
      await _guardarCategorias();
    } else {
      final List<dynamic> decodificado = jsonDecode(jsonGuardado);
      _categorias = decodificado.map((e) => e as Map<String, dynamic>).toList();
    }
    setState(() {});
  }

  Future<void> _guardarCategorias() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DBKeys.categoriasJson, jsonEncode(_categorias));
  }

  void _mostrarDialogoNuevaCategoria() {
    final controlador = TextEditingController();
    String iconoSeleccionado = 'general';

    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(l10n.nuevaCategoria),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controlador,
                    decoration: InputDecoration(labelText: l10n.nombre),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: AppNumbers.paddingStandard),
                  Text(l10n.seleccionaIcono),
                  const SizedBox(height: AppNumbers.paddingCorto),
                  Expanded(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: AppNumbers.paddingCorto,
                        mainAxisSpacing: AppNumbers.paddingCorto,
                      ),
                      itemCount: mapaIconos.length,
                      itemBuilder: (context, index) {
                        String clave = mapaIconos.keys.elementAt(index);
                        return GestureDetector(
                          onTap: () => setStateDialog(() => iconoSeleccionado = clave),
                          child: Container(
                            decoration: BoxDecoration(
                              color: iconoSeleccionado == clave ? Theme.of(context).colorScheme.primary.withValues(alpha: AppNumbers.opacityMedia) : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppNumbers.radiusStandard),
                              border: Border.all(color: iconoSeleccionado == clave ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: Icon(mapaIconos[clave], color: iconoSeleccionado == clave ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelar)),
              ElevatedButton(
                onPressed: () {
                  final nombre = controlador.text.trim().toLowerCase();
                  // Evita duplicados tanto por el nombre guardado como por el traducido
                  bool existe = _categorias.any((c) {
                    final guardado = c['nombre'].toString();
                    return guardado.toLowerCase() == nombre || l10n.nombreCategoria(guardado).toLowerCase() == nombre;
                  });
                  if (nombre.isNotEmpty && !existe) {
                    setState(() {
                      _categorias.add({'nombre': controlador.text.trim(), 'icono': iconoSeleccionado});
                    });
                    _guardarCategorias();
                    Navigator.pop(context);
                  }
                },
                child: Text(l10n.anadir),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categorias)),
      body: ListView.builder(
        itemCount: _categorias.length,
        itemBuilder: (context, index) {
          final cat = _categorias[index];
          return ListTile(
            leading: Icon(mapaIconos[cat['icono']] ?? Icons.label, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.nombreCategoria(cat['nombre'])),
            trailing: IconButton(
              icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: AppLocalizations.of(context).borrar,
              onPressed: () {
                setState(() => _categorias.removeAt(index));
                _guardarCategorias();
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoNuevaCategoria,
        child: const Icon(Icons.add),
      ),
    );
  }
}