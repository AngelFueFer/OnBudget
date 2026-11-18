import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/servicios/importador_csv.dart';
import 'package:presupuesto_familiar/servicios/importador_norma43.dart';

// Importación de extractos: leer el fichero, sugerir categoría, evitar duplicados e importar
// solo los movimientos que el usuario elija (o ninguno, para actualizar solo el saldo).
class ServicioExtractos {
  // Acceso a la base de datos. Se puede sustituir en los tests.
  static Future<List<Transaccion>> Function() movimientosExistentes = () => DBHelper().obtenerTransacciones();
  static Future<void> Function(Transaccion) insertar = (t) => DBHelper().insertarTransaccion(t);

  // Norma 43 suele venir en Latin-1; CSV de neobancos en UTF-8
  static List<ExtractoCuenta> leer(List<int> bytes) {
    String contenido;
    try {
      contenido = utf8.decode(bytes);
    } on FormatException {
      contenido = latin1.decode(bytes);
    }
    if (ImportadorNorma43.pareceNorma43(contenido)) return ImportadorNorma43.leer(contenido);
    return [ImportadorCsv.leer(contenido)];
  }

  // Palabra clave (sin tildes, minúsculas) -> categoría por defecto
  static const Map<String, List<String>> _palabrasClave = {
    'Supermercado': ['mercadona', 'carrefour', 'lidl', 'aldi', 'eroski', 'alcampo', 'consum', 'hipercor', 'supermerc', 'bonpreu', 'ahorramas', 'gadis', 'froiz', 'dia retail', 'supermercados dia'],
    'Transporte': ['renfe', 'metro', 'uber', 'cabify', 'bolt', 'repsol', 'cepsa', 'galp', 'gasolin', 'parking', 'emt ', 'autopista', 'peaje', 'blablacar', 'vueling', 'iberia', 'ryanair'],
    'Restaurantes': ['restaur', 'burger', 'mcdonald', 'telepizza', 'just eat', 'glovo', 'uber eats', 'cafeteria', 'starbucks', 'taberna', 'kfc', 'domino'],
    'Luz': ['iberdrola', 'endesa', 'naturgy', 'holaluz', 'repsol luz', 'electric'],
    'Agua': ['aqualia', 'canal de isabel', 'aguas de', 'emasesa', 'agbar'],
    'Teléfono': ['movistar', 'vodafone', 'orange', 'digi', 'yoigo', 'pepephone', 'lowi', 'masmovil', 'simyo', 'o2 '],
    'Ropa': ['zara', 'primark', 'h&m', 'pull&bear', 'pull and bear', 'mango', 'bershka', 'stradivarius', 'shein', 'kiabi'],
    'Ocio': ['netflix', 'spotify', 'hbo', 'disney', 'prime video', 'cine', 'steam', 'playstation', 'ticketmaster', 'gym', 'gimnasio'],
    'Hogar': ['ikea', 'leroy', 'bricomart', 'alquiler', 'comunidad', 'seguro hogar', 'amazon'],
  };

  static String sugerirCategoria(MovimientoExtracto movimiento) {
    final concepto = _simplificar(movimiento.concepto);
    if (movimiento.esIngreso) {
      return RegExp(r'nomina|salario|payroll|salary').hasMatch(concepto) ? AppStrings.categoriaSalario : AppStrings.categoriaGeneral;
    }
    for (final entrada in _palabrasClave.entries) {
      if (entrada.value.any(concepto.contains)) {
        return entrada.key;
      }
    }
    return AppStrings.categoriaGeneral;
  }

  // Mismo día, mismo importe, mismo signo y mismo concepto que un movimiento ya guardado
  static bool yaImportado(MovimientoExtracto movimiento, List<Transaccion> existentes) {
    final concepto = movimiento.concepto.trim().toLowerCase();
    return existentes.any((t) =>
        t.montoEnCentimos == movimiento.centimos &&
        t.esIngreso == movimiento.esIngreso &&
        t.fecha.year == movimiento.fecha.year &&
        t.fecha.month == movimiento.fecha.month &&
        t.fecha.day == movimiento.fecha.day &&
        t.concepto.trim().toLowerCase() == concepto);
  }

  // Índices de los movimientos que ya están en el presupuesto.
  // Siempre cuenta la coincidencia exacta (yaImportado). Con margenDias > 0 (sincronización con el banco)
  // también cuenta el mismo importe y signo con hasta esos días de diferencia aunque el concepto cambie:
  // el gasto apuntado al momento por una notificación ("MERCADONA") es el que el banco contabiliza
  // días después ("COMPRA TARJ. MERCADONA VALENCIA"). Cada apunte existente solo cubre un movimiento,
  // así dos cafés del mismo importe no se tapan entre sí, y se empareja con el de fecha más cercana.
  static Set<int> indicesYaImportados(List<MovimientoExtracto> movimientos, List<Transaccion> existentes, {int margenDias = 0}) {
    final resultado = <int>{};
    for (var i = 0; i < movimientos.length; i++) {
      if (yaImportado(movimientos[i], existentes)) resultado.add(i);
    }
    if (margenDias <= 0) return resultado;

    // Los apuntes que ya explican una coincidencia exacta no se reutilizan
    final libres = existentes
        .where((t) => !resultado.any((i) => _coincideExacto(movimientos[i], t)))
        .toList();
    final pendientes = [for (var i = 0; i < movimientos.length; i++) if (!resultado.contains(i)) i];
    final parejas = <(int, Transaccion, int)>[];
    for (final i in pendientes) {
      final m = movimientos[i];
      for (final t in libres) {
        if (t.montoEnCentimos != m.centimos || t.esIngreso != m.esIngreso) continue;
        final dias = _dia(t.fecha).difference(_dia(m.fecha)).inDays.abs();
        if (dias <= margenDias) parejas.add((i, t, dias));
      }
    }
    parejas.sort((a, b) => a.$3.compareTo(b.$3));
    final usados = <Transaccion>{};
    for (final (i, t, _) in parejas) {
      if (resultado.contains(i) || usados.contains(t)) continue;
      resultado.add(i);
      usados.add(t);
    }
    return resultado;
  }

  static bool _coincideExacto(MovimientoExtracto m, Transaccion t) => yaImportado(m, [t]);

  static DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

  // Los movimientos elegidos entran en la Cuenta Mensual como cualquier gasto o ingreso
  static Future<void> importar(List<(MovimientoExtracto, String)> elegidos) async {
    for (final (movimiento, categoria) in elegidos) {
      await insertar(Transaccion(
        montoEnCentimos: movimiento.centimos,
        concepto: movimiento.concepto.isEmpty ? categoria : movimiento.concepto,
        fecha: movimiento.fecha,
        categoria: categoria,
        esIngreso: movimiento.esIngreso,
        tarroDestino: AppStrings.cuentaMensual,
      ));
    }
  }

  // Categorías del usuario (las mismas que en el formulario)
  static Future<List<String>> categorias() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(DBKeys.categoriasJson);
    final List<dynamic> lista = guardado == null ? AppStrings.categoriasConIconoDefecto : jsonDecode(guardado);
    return lista.map((e) => e['nombre'].toString()).toList();
  }

  static String _simplificar(String texto) {
    const conTilde = 'áàäâéèëêíìïîóòöôúùüûñç';
    const sinTilde = 'aaaaeeeeiiiioooouuuunc';
    var resultado = texto.toLowerCase();
    for (var i = 0; i < conTilde.length; i++) {
      resultado = resultado.replaceAll(conTilde[i], sinTilde[i]);
    }
    return resultado;
  }
}
