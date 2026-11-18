import 'package:presupuesto_familiar/utilidades/iban.dart';

// Banco del catálogo. Sirve para reconocer el banco a partir del IBAN y para elegirlo de una lista.
class BancoCatalogo {
  final String id;
  final String nombre;
  // Códigos de banco tal y como aparecen en el IBAN, con el país delante: 'ES0049', 'LT32500', 'NLBUNQ'
  final List<String> codigos;
  final int color; // Color de marca para el avatar (ARGB)
  final bool neobanco;
  final List<String> alias; // Otros nombres con los que se busca ('La Caixa', 'Santander'…)
  // Apps de Android del banco, para leer sus notificaciones de pago (EXPERIMENTAL; ampliar con muestras reales)
  final List<String> paquetesAndroid;

  const BancoCatalogo({
    required this.id,
    required this.nombre,
    this.codigos = const [],
    required this.color,
    this.neobanco = false,
    this.alias = const [],
    this.paquetesAndroid = const [],
  });

  // Iniciales para el avatar: 'Banco Santander' -> 'BS', 'BBVA' -> 'BB'
  String get iniciales {
    final palabras = nombre.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (palabras.length == 1) return palabras.first.substring(0, palabras.first.length < 2 ? 1 : 2).toUpperCase();
    return '${palabras[0][0]}${palabras[1][0]}'.toUpperCase();
  }
}

// 30 bancos principales de España + 10 neobancos.
// Códigos de entidad del Registro de Entidades del Banco de España. Los neobancos que no
// tienen un código fiable (cambian de IBAN extranjero a español) solo se reconocen por nombre.
class CatalogoBancos {
  static const List<BancoCatalogo> bancos = [
    BancoCatalogo(id: 'santander', nombre: 'Banco Santander', codigos: ['ES0049'], color: 0xFFEC0000, alias: ['Santander'], paquetesAndroid: ['es.bancosantander.apps']),
    BancoCatalogo(id: 'bbva', nombre: 'BBVA', codigos: ['ES0182'], color: 0xFF004481, paquetesAndroid: ['com.bbva.bbvacontigo']),
    BancoCatalogo(id: 'caixabank', nombre: 'CaixaBank', codigos: ['ES2100'], color: 0xFF007EAE, alias: ['La Caixa', 'Caixa'], paquetesAndroid: ['es.lacaixa.mobile.android.newwapicon']),
    BancoCatalogo(id: 'sabadell', nombre: 'Banco Sabadell', codigos: ['ES0081'], color: 0xFF006DFF, alias: ['Sabadell'], paquetesAndroid: ['net.inverline.bancosabadell.officelocator.android']),
    BancoCatalogo(id: 'bankinter', nombre: 'Bankinter', codigos: ['ES0128'], color: 0xFFFF6600, paquetesAndroid: ['com.bankinter.launcher']),
    BancoCatalogo(id: 'unicaja', nombre: 'Unicaja', codigos: ['ES2103'], color: 0xFF00A04A, alias: ['Liberbank']),
    BancoCatalogo(id: 'abanca', nombre: 'Abanca', codigos: ['ES2080'], color: 0xFF0055A5),
    BancoCatalogo(id: 'kutxabank', nombre: 'Kutxabank', codigos: ['ES2095'], color: 0xFFE2001A, alias: ['BBK', 'Vital', 'Kutxa']),
    BancoCatalogo(id: 'ibercaja', nombre: 'Ibercaja', codigos: ['ES2085'], color: 0xFF1D3E8F),
    BancoCatalogo(id: 'cajamar', nombre: 'Cajamar', codigos: ['ES3058'], color: 0xFF00965E, alias: ['Grupo Cooperativo Cajamar']),
    BancoCatalogo(id: 'ing', nombre: 'ING', codigos: ['ES1465'], color: 0xFFFF6200, alias: ['ING Direct', 'Cuenta Naranja'], paquetesAndroid: ['www.ingdirect.nativeframe']),
    BancoCatalogo(id: 'openbank', nombre: 'Openbank', codigos: ['ES0073'], color: 0xFFEC0000, paquetesAndroid: ['es.openbank.mobile']),
    BancoCatalogo(id: 'deutsche', nombre: 'Deutsche Bank', codigos: ['ES0019'], color: 0xFF0018A8),
    BancoCatalogo(id: 'march', nombre: 'Banca March', codigos: ['ES0061'], color: 0xFF8C1D40, alias: ['March']),
    BancoCatalogo(id: 'cajasur', nombre: 'Cajasur', codigos: ['ES0237'], color: 0xFF009639),
    BancoCatalogo(id: 'laboral', nombre: 'Laboral Kutxa', codigos: ['ES3035'], color: 0xFF006E3B, alias: ['Caja Laboral']),
    BancoCatalogo(id: 'ruralnavarra', nombre: 'Caja Rural de Navarra', codigos: ['ES3008'], color: 0xFF007A3D, alias: ['Caja Rural']),
    BancoCatalogo(id: 'globalcaja', nombre: 'Globalcaja', codigos: ['ES3190'], color: 0xFF009B3A, alias: ['Caja Rural']),
    BancoCatalogo(id: 'eurocaja', nombre: 'Eurocaja Rural', codigos: ['ES3081'], color: 0xFF00843D, alias: ['Caja Rural Castilla-La Mancha']),
    BancoCatalogo(id: 'ruralsur', nombre: 'Caja Rural del Sur', codigos: ['ES3187'], color: 0xFF00753B, alias: ['Caja Rural']),
    BancoCatalogo(id: 'ruralgranada', nombre: 'Caja Rural de Granada', codigos: ['ES3023'], color: 0xFF008C45, alias: ['Caja Rural']),
    BancoCatalogo(id: 'ingenieros', nombre: 'Caja de Ingenieros', codigos: ['ES3025'], color: 0xFF003B71),
    BancoCatalogo(id: 'ontinyent', nombre: 'Caixa Ontinyent', codigos: ['ES2045'], color: 0xFF0070B8),
    BancoCatalogo(id: 'colonya', nombre: 'Colonya Caixa Pollença', codigos: ['ES2056'], color: 0xFF5A9E2F, alias: ['Colonya']),
    BancoCatalogo(id: 'mediolanum', nombre: 'Banco Mediolanum', codigos: ['ES0186'], color: 0xFF00205B, alias: ['Mediolanum']),
    BancoCatalogo(id: 'evo', nombre: 'EVO Banco', codigos: ['ES0239'], color: 0xFF00B2A9, alias: ['EVO'], paquetesAndroid: ['es.evobanco.bancamovil']),
    BancoCatalogo(id: 'targobank', nombre: 'Targobank', codigos: ['ES0216'], color: 0xFF003F7D),
    BancoCatalogo(id: 'renta4', nombre: 'Renta 4 Banco', codigos: ['ES0083'], color: 0xFF0B2A4A, alias: ['Renta 4']),
    BancoCatalogo(id: 'selfbank', nombre: 'Self Bank', codigos: ['ES1490'], color: 0xFF00A3E0, alias: ['Singular Bank']),
    BancoCatalogo(id: 'triodos', nombre: 'Triodos Bank', codigos: ['ES1491'], color: 0xFF00594F, alias: ['Triodos']),

    // --- Neobancos ---
    BancoCatalogo(id: 'revolut', nombre: 'Revolut', codigos: ['ES1583', 'LT32500'], color: 0xFF191C1F, neobanco: true, paquetesAndroid: ['com.revolut.revolut']),
    BancoCatalogo(id: 'n26', nombre: 'N26', codigos: ['DE10011001'], color: 0xFF36A18B, neobanco: true, paquetesAndroid: ['de.number26.android']),
    BancoCatalogo(id: 'bunq', nombre: 'bunq', codigos: ['NLBUNQ'], color: 0xFF2F9E44, neobanco: true, paquetesAndroid: ['com.bunq.android']),
    BancoCatalogo(id: 'wise', nombre: 'Wise', codigos: ['BE967'], color: 0xFF163300, neobanco: true, alias: ['TransferWise'], paquetesAndroid: ['com.transferwise.android']),
    BancoCatalogo(id: 'traderepublic', nombre: 'Trade Republic', color: 0xFF000000, neobanco: true, paquetesAndroid: ['de.traderepublic.app']),
    BancoCatalogo(id: 'myinvestor', nombre: 'MyInvestor', codigos: ['ES1544'], color: 0xFF2E2A5B, neobanco: true),
    BancoCatalogo(id: 'imagin', nombre: 'imagin', color: 0xFF00D2A0, neobanco: true, alias: ['imaginBank'], paquetesAndroid: ['com.imaginbank.app']), // usa IBAN de CaixaBank
    BancoCatalogo(id: 'vivid', nombre: 'Vivid Money', color: 0xFF6A3CFF, neobanco: true, alias: ['Vivid']),
    BancoCatalogo(id: 'pibank', nombre: 'Pibank', codigos: ['ES0235'], color: 0xFFFFC72C, neobanco: true, alias: ['Banco Pichincha']),
    BancoCatalogo(id: 'b100', nombre: 'B100', color: 0xFF00C389, neobanco: true), // usa IBAN de Abanca
  ];

  static List<BancoCatalogo> get tradicionales => bancos.where((b) => !b.neobanco).toList();
  static List<BancoCatalogo> get neobancos => bancos.where((b) => b.neobanco).toList();

  static BancoCatalogo? porId(String? id) => bancos.where((b) => b.id == id).firstOrNull;

  // Banco al que pertenece una app de Android (para la lectura de notificaciones)
  static BancoCatalogo? porPaquete(String? paquete) =>
      paquete == null ? null : bancos.where((b) => b.paquetesAndroid.contains(paquete)).firstOrNull;

  // Banco al que pertenece un IBAN (aunque el IBAN aún no esté completo, basta con el código de banco)
  static BancoCatalogo? detectar(String iban) {
    final codigo = Iban.codigoBanco(iban);
    if (codigo == null) return null;
    final clave = '${Iban.pais(iban)}$codigo';
    return bancos.where((b) => b.codigos.contains(clave)).firstOrNull;
  }

  // Búsqueda sin tildes ni mayúsculas en nombre y alias
  static List<BancoCatalogo> buscar(String texto) {
    final consulta = _simplificar(texto);
    if (consulta.isEmpty) return bancos;
    return bancos
        .where((b) => [b.nombre, ...b.alias].any((n) => _simplificar(n).contains(consulta)))
        .toList();
  }

  static String _simplificar(String texto) {
    const conTilde = 'áàäâéèëêíìïîóòöôúùüûñç';
    const sinTilde = 'aaaaeeeeiiiioooouuuunc';
    var resultado = texto.toLowerCase().trim();
    for (var i = 0; i < conTilde.length; i++) {
      resultado = resultado.replaceAll(conTilde[i], sinTilde[i]);
    }
    return resultado;
  }
}
