import 'dart:io';

import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/servicios/servicio_tiquets.dart';

// Muestra la foto del tiquet a pantalla completa, con zoom
Future<void> abrirTiquet(BuildContext context, String nombre) async {
  final archivo = await ServicioTiquets.archivo(nombre);
  if (!context.mounted) return;
  if (archivo == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).tiquetNoEncontrado)));
    return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => VisorTiquet(archivo: archivo)));
}

class VisorTiquet extends StatelessWidget {
  final File archivo;

  const VisorTiquet({super.key, required this.archivo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).tiquet),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: Image.file(archivo)),
      ),
    );
  }
}
