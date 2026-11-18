import 'dart:io';

import 'package:onbudget_servidor/onbudget_servidor.dart';

Future<void> main(List<String> args) async {
  final codigo = await ejecutar(args);
  // "servir" se queda escuchando; el resto de comandos termina aquí
  if (args.isNotEmpty && args.first != 'servir') exit(codigo);
}
