import 'dart:convert';

import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/sincronizacion/reloj_hibrido.dart';

// Columnas que gestiona la sincronización y nunca se fusionan como datos del usuario.
// El id local tampoco: cada dispositivo tiene el suyo, lo que es común es el uuid.
const Set<String> columnasMeta = {
  DBKeys.columnId,
  DBKeys.columnUuid,
  DBKeys.columnRelojes,
  DBKeys.columnModificado,
  DBKeys.columnDispositivo,
};

Map<String, String> leerRelojes(Object? json) {
  if (json is! String || json.isEmpty) return {};
  try {
    final mapa = jsonDecode(json);
    if (mapa is! Map) return {};
    return mapa.map((k, v) => MapEntry(k.toString(), v.toString()));
  } on FormatException {
    // Relojes ilegibles: se tratan como "nunca escrito" y gana cualquier cambio remoto
    return {};
  }
}

// Marca con [reloj] los campos de [nueva] que cambian respecto a [anterior] (null = fila nueva)
// y devuelve los relojes resultantes. Los campos que no cambian conservan su reloj.
Map<String, String> marcarCambios(
  Map<String, Object?>? anterior,
  Map<String, Object?> nueva,
  Map<String, String> relojesAnteriores,
  String reloj,
) {
  final resultado = Map<String, String>.from(relojesAnteriores);
  for (final campo in nueva.keys) {
    if (columnasMeta.contains(campo)) continue;
    if (anterior == null || !anterior.containsKey(campo) || anterior[campo] != nueva[campo]) {
      resultado[campo] = reloj;
    }
  }
  return resultado;
}

// Fusión "último que escribe gana" campo a campo: de cada campo se queda el valor con el reloj
// más reciente. Así, si un móvil cambia el importe y otro la categoría, se conservan ambos.
// [local] es null si la fila aún no existe aquí. Devuelve la fila resultante, sin id local.
Map<String, Object?> fusionarFila({
  required Map<String, Object?>? local,
  required Map<String, Object?> remota,
}) {
  final relojesLocales = leerRelojes(local?[DBKeys.columnRelojes]);
  final relojesRemotos = leerRelojes(remota[DBKeys.columnRelojes]);

  final resultado = <String, Object?>{
    for (final e in (local ?? const <String, Object?>{}).entries)
      if (e.key != DBKeys.columnId) e.key: e.value,
  };
  final relojes = Map<String, String>.from(relojesLocales);

  for (final campo in remota.keys) {
    if (columnasMeta.contains(campo)) continue;
    final relojRemoto = relojesRemotos[campo];
    // Un campo que el remoto trae sin reloj solo rellena huecos (versión antigua de la app)
    final gana = local == null ||
        !resultado.containsKey(campo) ||
        RelojHibrido.esPosterior(relojRemoto, relojesLocales[campo]);
    if (gana) {
      resultado[campo] = remota[campo];
      if (relojRemoto != null) relojes[campo] = relojRemoto;
    }
  }

  resultado[DBKeys.columnUuid] = remota[DBKeys.columnUuid] ?? local?[DBKeys.columnUuid];
  resultado[DBKeys.columnRelojes] = jsonEncode(relojes);
  final modificado = relojes.values.fold<String?>(null, (max, r) => RelojHibrido.esPosterior(r, max) ? r : max);
  resultado[DBKeys.columnModificado] = modificado;
  final ganador = modificado == null ? null : RelojHibrido.leer(modificado);
  resultado[DBKeys.columnDispositivo] = ganador?.dispositivo ?? local?[DBKeys.columnDispositivo];
  return resultado;
}
