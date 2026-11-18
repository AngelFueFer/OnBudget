// Identificadores que se guardan en base de datos / SharedPreferences.
// NO se traducen: cambiarlos rompería los datos ya guardados.
// Los textos visibles de la interfaz están en lib/l10n/ (AppLocalizations).
class AppStrings {
  // Nombres de cuentas (columna tarroDestino)
  static const String cuentaMensual = 'Cuenta Mensual';
  static const String ahorro = 'Ahorro';

  // Métodos de pago (columna metodoPago); con tarjeta, su nombre va en la columna tarjeta
  static const String metodoEfectivo = 'efectivo';
  static const String metodoTarjeta = 'tarjeta';

  // Tipos de inversión (columna tipo de activos_financieros); sin tipo = acción
  static const String tipoMateriaPrima = 'materiaPrima';
  static const String tipoAccion = 'accion';
  static const String tipoEtf = 'etf';
  static const String tipoRentaFija = 'rentaFija';
  static const String tipoDerivado = 'derivado';
  static const String tipoCripto = 'cripto';
  static const List<String> tiposInversion = [tipoMateriaPrima, tipoAccion, tipoEtf, tipoRentaFija, tipoDerivado, tipoCripto];

  // Conceptos de las transacciones automáticas de nómina
  static const String nominaPartePresupuesto = 'Nómina (Parte Presupuesto)';
  static const String nominaParteAhorro = 'Nómina (Parte Ahorro)';

  // Traspaso del presupuesto no gastado a Ahorro: se guarda como 'Remanente AAAA-MM'
  static const String prefijoRemanente = 'Remanente ';
  static String conceptoRemanente(String mesAnio) => '$prefijoRemanente$mesAnio';

  // Cobertura del saldo negativo con la cuenta de ahorro principal: 'Déficit AAAA-MM'
  static const String prefijoDeficit = 'Déficit ';
  static String conceptoDeficit(String mesAnio) => '$prefijoDeficit$mesAnio';

  // Categorías especiales
  static const String categoriaSalario = 'Salario';
  static const String categoriaRemanente = 'Remanente';
  static const String categoriaDeficit = 'Déficit';
  static const String categoriaGeneral = 'General';
  static const String categoriaHogar = 'Hogar';

  // Categorías de relleno para los accesos rápidos de la pantalla principal
  static const List<String> categoriasDefecto = [
    'Supermercado',
    'Transporte',
    'Restaurantes',
    'Hogar',
    'Ocio',
    'Luz',
    'Agua',
    'Ropa',
  ];

  // Categorías disponibles para los gastos fijos
  static const List<String> categoriasGastosFijos = [
    'General',
    'Comida',
    'Hogar',
    'Transporte',
    'Ocio',
  ];

  // Categorías iniciales con su clave de icono (ver diccionario_iconos.dart)
  static const List<Map<String, String>> categoriasConIconoDefecto = [
    {'nombre': 'Transporte', 'icono': 'transporte'},
    {'nombre': 'Supermercado', 'icono': 'supermercado'},
    {'nombre': 'Restaurantes', 'icono': 'restaurantes'},
    {'nombre': 'Hogar', 'icono': 'hogar'},
    {'nombre': 'Ropa', 'icono': 'ropa'},
    {'nombre': 'Teléfono', 'icono': 'telefono'},
    {'nombre': 'Luz', 'icono': 'luz'},
    {'nombre': 'Agua', 'icono': 'agua'},
    {'nombre': 'Ocio', 'icono': 'ocio'},
    {'nombre': 'Salario', 'icono': 'salario'},
    {'nombre': 'General', 'icono': 'general'},
  ];

  // Idiomas disponibles: código guardado -> nombre nativo (no se traduce)
  static const Map<String, String> idiomasDisponibles = {
    'es': 'Español',
    'en': 'English',
    'fr': 'Français',
    'de': 'Deutsch',
    'pt': 'Português',
    'it': 'Italiano',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'ca': 'Català',
    'tr': 'Türkçe',
    'zh': '简体中文',
    'ja': '日本語',
  };

  // Colores de acento (DBKeys.colorAcento). Por defecto, el azul del logo
  static const String acentoBlanco = 'blanco';
  static const String acentoAzul = 'azul';
  static const String acentoVerde = 'verde';
  static const String acentoMorado = 'morado';
  static const String acentoNaranja = 'naranja';
  static const String acentoRosa = 'rosa';
  static const String acentoPorDefecto = acentoAzul;

  // Dónde se guardan los datos (DBKeys.modoAlmacenamiento)
  static const String almacenamientoLocal = 'local';
  static const String almacenamientoServidor = 'servidor';
}
