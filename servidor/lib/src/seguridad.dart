import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _aleatorio = Random.secure();

Uint8List bytesAleatorios(int longitud) =>
    Uint8List.fromList(List<int>.generate(longitud, (_) => _aleatorio.nextInt(256)));

// Token opaco en base64url (para sesiones de dispositivo)
String nuevoToken() => base64Url.encode(bytesAleatorios(32)).replaceAll('=', '');

// Código de invitación legible para copiarlo a mano: 4 grupos de 4 caracteres sin ambiguos (0/O, 1/I)
String nuevoCodigoInvitacion() {
  const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final grupos = List.generate(4, (_) => List.generate(4, (_) => alfabeto[_aleatorio.nextInt(alfabeto.length)]).join());
  return grupos.join('-');
}

String nuevoUuid() {
  final b = bytesAleatorios(16);
  b[6] = (b[6] & 0x0F) | 0x40;
  b[8] = (b[8] & 0x3F) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

// Los tokens e invitaciones se guardan solo como hash: si alguien copia la base de datos no puede usarlos.
// SHA-256 basta porque son valores aleatorios de alta entropía, no contraseñas.
String hashDe(String valor) => sha256.convert(utf8.encode(valor)).toString();

// La "huella de acceso" que envía la app ya sale de Argon2id en el móvil (nunca llega la contraseña).
// Aquí se le aplica sal propia para que la base de datos no guarde ni siquiera esa huella.
String hashConSal(List<int> sal, List<int> huella) => sha256.convert([...sal, ...huella]).toString();

// Comparación en tiempo constante, para no filtrar información por lo que tarda
bool igualesSeguro(String a, String b) {
  if (a.length != b.length) return false;
  var diferencia = 0;
  for (var i = 0; i < a.length; i++) {
    diferencia |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diferencia == 0;
}

// Normaliza un código de invitación tecleado (minúsculas, espacios, sin guiones)
String normalizarInvitacion(String codigo) {
  final limpio = codigo.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (limpio.length != 16) return limpio;
  return [for (var i = 0; i < 16; i += 4) limpio.substring(i, i + 4)].join('-');
}
