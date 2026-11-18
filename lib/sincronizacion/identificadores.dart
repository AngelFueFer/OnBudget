import 'dart:math';

// UUID v4 aleatorio (RFC 4122), sin dependencias externas.
// Random.secure para que dos dispositivos nunca generen el mismo id.
String nuevoUuid([Random? aleatorio]) {
  final r = aleatorio ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // versión 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variante RFC 4122
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
