import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Fotos de los tiquets de los gastos. Se copian a la carpeta privada de la app y en la base de datos
// solo se guarda el nombre del archivo (la ruta absoluta cambia entre instalaciones en iOS).
class ServicioTiquets {
  static const String _carpeta = 'tiquets';

  static Future<Directory> _directorio() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _carpeta));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // Fotos con la cámara o la galería del sistema: todo en local, sin servicios externos.
  // Devuelven el nombre guardado o null si se cancela.
  static Future<String?> hacerFoto() => _desdePicker(ImageSource.camera);

  static Future<String?> elegirDeGaleria() => _desdePicker(ImageSource.gallery);

  static Future<String?> _desdePicker(ImageSource origen) async {
    final foto = await ImagePicker().pickImage(source: origen, imageQuality: 85, maxWidth: 2000);
    if (foto == null) return null;
    return _guardar(File(foto.path));
  }

  static Future<String> _guardar(File origen) async {
    final dir = await _directorio();
    final extension = p.extension(origen.path).isEmpty ? '.jpg' : p.extension(origen.path);
    final nombre = 'tiquet_${DateTime.now().millisecondsSinceEpoch}$extension';
    await origen.copy(p.join(dir.path, nombre));
    return nombre;
  }

  static Future<File?> archivo(String? nombre) async {
    if (nombre == null) return null;
    final archivo = File(p.join((await _directorio()).path, nombre));
    return await archivo.exists() ? archivo : null;
  }

  static Future<void> borrar(String? nombre) async {
    final existente = await archivo(nombre);
    if (existente != null) await existente.delete();
  }
}
