import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'seguridad.dart';

// Contraseña del panel de administración (ADMIN_TOKEN).
// Se recomienda guardarla como "$pbkdf2-sha256$<iteraciones>$<sal b64>$<hash b64>" (comando
// "onbudget-servidor admin hash") para no dejarla en claro en el docker-compose. También se
// acepta en texto plano, con un aviso al arrancar, igual que Vaultwarden.

const String _prefijo = r'$pbkdf2-sha256$';
const String _separador = r'$';
const int iteracionesTokenAdmin = 600000;

List<int> pbkdf2Sha256(List<int> clave, List<int> sal, int iteraciones, int longitud) {
  final hmac = Hmac(sha256, clave);
  final resultado = <int>[];
  for (var bloque = 1; resultado.length < longitud; bloque++) {
    var u = hmac.convert([
      ...sal,
      (bloque >> 24) & 0xFF,
      (bloque >> 16) & 0xFF,
      (bloque >> 8) & 0xFF,
      bloque & 0xFF,
    ]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iteraciones; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    resultado.addAll(t);
  }
  return resultado.sublist(0, longitud);
}

String hashTokenAdmin(String token, {int iteraciones = iteracionesTokenAdmin}) {
  final sal = bytesAleatorios(16);
  final hash = pbkdf2Sha256(utf8.encode(token), sal, iteraciones, 32);
  return [_prefijo + iteraciones.toString(), base64.encode(sal), base64.encode(hash)].join(_separador);
}

bool tokenAdminEsHash(String configurado) => configurado.startsWith(_prefijo);

bool comprobarTokenAdmin(String introducido, String configurado) {
  if (!tokenAdminEsHash(configurado)) {
    // Texto plano: se comparan hashes para que la comparación no dependa de la longitud
    return igualesSeguro(hashDe(introducido), hashDe(configurado));
  }
  final partes = configurado.substring(_prefijo.length).split(_separador);
  if (partes.length != 3) return false;
  final iteraciones = int.tryParse(partes[0]);
  if (iteraciones == null || iteraciones < 1) return false;
  try {
    final sal = base64.decode(partes[1]);
    final esperado = base64.decode(partes[2]);
    final calculado = pbkdf2Sha256(utf8.encode(introducido), sal, iteraciones, esperado.length);
    return igualesSeguro(base64.encode(calculado), base64.encode(esperado));
  } on FormatException {
    return false;
  }
}
