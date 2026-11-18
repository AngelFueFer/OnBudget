import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/l10n/traducciones/es.dart';
import 'package:presupuesto_familiar/l10n/traducciones/en.dart';
import 'package:presupuesto_familiar/l10n/traducciones/fr.dart';
import 'package:presupuesto_familiar/l10n/traducciones/de.dart';
import 'package:presupuesto_familiar/l10n/traducciones/pt.dart';
import 'package:presupuesto_familiar/l10n/traducciones/it.dart';
import 'package:presupuesto_familiar/l10n/traducciones/nl.dart';
import 'package:presupuesto_familiar/l10n/traducciones/pl.dart';
import 'package:presupuesto_familiar/l10n/traducciones/ca.dart';
import 'package:presupuesto_familiar/l10n/traducciones/tr.dart';
import 'package:presupuesto_familiar/l10n/traducciones/zh.dart';
import 'package:presupuesto_familiar/l10n/traducciones/ja.dart';

class AppLocalizations {
  final String codigoIdioma;

  AppLocalizations(this.codigoIdioma);

  static const String idiomaPorDefecto = 'es';

  static const Map<String, Map<String, String>> _traducciones = {
    'es': es,
    'en': en,
    'fr': fr,
    'de': de,
    'pt': pt,
    'it': it,
    'nl': nl,
    'pl': pl,
    'ca': ca,
    'tr': tr,
    'zh': zh,
    'ja': ja,
  };

  // Solo para tests: todas las tablas, para comprobar que ningún idioma se queda atrás
  static Map<String, Map<String, String>> get tablasTraduccion => _traducciones;

  static List<Locale> get idiomasSoportados =>
      _traducciones.keys.map((codigo) => Locale(codigo)).toList();

  static bool esSoportado(String? codigo) => _traducciones.containsKey(codigo);

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  // Busca la clave en el idioma actual; si falta, usa el español
  String _t(String clave) {
    return _traducciones[codigoIdioma]?[clave] ?? es[clave] ?? clave;
  }

  String _formatear(String clave, Map<String, String> valores) {
    var texto = _t(clave);
    valores.forEach((nombre, valor) => texto = texto.replaceAll('{$nombre}', valor));
    return texto;
  }

  // --- Traducción de valores guardados en base de datos ---

  // Traduce las categorías por defecto; las creadas por el usuario se muestran tal cual
  String nombreCategoria(String categoria) {
    return _traducciones[codigoIdioma]?['cat.$categoria'] ?? categoria;
  }

  String nombreCuenta(String cuenta) {
    if (cuenta == AppStrings.cuentaMensual) return cuentaMensual;
    if (cuenta == AppStrings.ahorro) return ahorro;
    return cuenta;
  }

  String concepto(String concepto) {
    if (concepto == AppStrings.nominaPartePresupuesto) return _t('nominaPartePresupuesto');
    if (concepto == AppStrings.nominaParteAhorro) return _t('nominaParteAhorro');
    final remanente = _formatearMes(concepto, AppStrings.prefijoRemanente, 'remanente');
    if (remanente != null) return remanente;
    final deficit = _formatearMes(concepto, AppStrings.prefijoDeficit, 'deficit');
    if (deficit != null) return deficit;
    return concepto;
  }

  // 'Remanente 2026-09' -> 'Remanente de septiembre de 2026' (según idioma); igual con 'Déficit 2026-09'
  String? _formatearMes(String concepto, String prefijo, String clave) {
    if (!concepto.startsWith(prefijo)) return null;
    final partes = concepto.substring(prefijo.length).split('-');
    if (partes.length != 2) return null;
    final mes = int.tryParse(partes[1]);
    if (mes == null || mes < 1 || mes > 12) return null;
    return _formatear(clave, {'mes': _t('mes$mes'), 'anio': partes[0]});
  }

  // --- General ---
  String get appTitle => _t('appTitle');
  String get editar => _t('editar');
  String get borrar => _t('borrar');
  String get guardar => _t('guardar');
  String get cancelar => _t('cancelar');
  String get anadir => _t('anadir');
  String get atras => _t('atras');
  String get siguiente => _t('siguiente');
  String get finalizar => _t('finalizar');
  String get categoria => _t('categoria');
  String get importe => _t('importe');
  String get nombre => _t('nombre');
  String get etiquetaConcepto => _t('etiquetaConcepto');

  // --- Cuentas ---
  String get cuentaMensual => _t('cuentaMensual');
  String get ahorro => _t('ahorro');
  String get inversion => _t('inversion');

  // --- Pantalla principal ---
  String get tituloPresupuestoMensual => _t('tituloPresupuestoMensual');
  String resumenPresupuesto(String gastado, String meta) =>
      _formatear('resumenPresupuesto', {'gastado': gastado, 'meta': meta});
  String rentabilidad(String valor, String porcentaje) =>
      _formatear('rentabilidad', {'valor': valor, 'porcentaje': porcentaje});
  String get sincronizandoBolsa => _t('sincronizandoBolsa');
  String get errorConexion => _t('errorConexion');
  String resumenActivo(String cantidad, String compra, String actual) =>
      _formatear('resumenActivo', {'cantidad': cantidad, 'compra': compra, 'actual': actual});
  String get ultimasCompras => _t('ultimasCompras');

  // --- Remuneración del ahorro ---
  String get remuneracionAhorro => _t('remuneracionAhorro');
  String tasaAnualCorta(String tasa) => _formatear('tasaAnualCorta', {'tasa': tasa});
  String get sinRemuneracion => _t('sinRemuneracion');
  String interesEstimado(String mensual, String anual) =>
      _formatear('interesEstimado', {'mensual': mensual, 'anual': anual});
  String get tasaAnual => _t('tasaAnual');
  String get remuneracionExplicacion => _t('remuneracionExplicacion');

  // --- Métodos de pago y tarjetas ---
  String get metodoPago => _t('metodoPago');
  String get efectivo => _t('efectivo');
  String get anadirTarjeta => _t('anadirTarjeta');
  String get misTarjetas => _t('misTarjetas');
  String get misTarjetasDescripcion => _t('misTarjetasDescripcion');
  String get nuevaTarjeta => _t('nuevaTarjeta');
  String get nombreTarjeta => _t('nombreTarjeta');
  String get nombreTarjetaAyuda => _t('nombreTarjetaAyuda');
  String get ningunaTarjeta => _t('ningunaTarjeta');
  String get debito => _t('debito');
  String get credito => _t('credito');
  String get ultimos4Digitos => _t('ultimos4Digitos');
  String get tarjetaRepetida => _t('tarjetaRepetida');
  String get cuentaGuardada => _t('cuentaGuardada');
  String get anadirSuTarjeta => _t('anadirSuTarjeta');

  // --- Importar tarjetas / lectura de notificaciones ---
  String get importarTarjetas => _t('importarTarjetas');
  String get tarjetasOnboardingDescripcion => _t('tarjetasOnboardingDescripcion');
  String get importarTarjetasDescripcion => _t('importarTarjetasDescripcion');
  String get enDesarrollo => _t('enDesarrollo');
  String get mostrarClave => _t('mostrarClave');
  String get ocultarClave => _t('ocultarClave');
  String get soloAndroid => _t('soloAndroid');
  String get permitirNotificaciones => _t('permitirNotificaciones');
  String get permisoConcedido => _t('permisoConcedido');
  String get bateriaRestringida => _t('bateriaRestringida');
  String get bateriaRestringidaDescripcion => _t('bateriaRestringidaDescripcion');
  String get quitarRestriccion => _t('quitarRestriccion');
  String get tarjetasDetectadas => _t('tarjetasDetectadas');
  String get sinTarjetasDetectadas => _t('sinTarjetasDetectadas');
  String get descartar => _t('descartar');

  // --- Filtro de movimientos ---
  String get filtrar => _t('filtrar');
  String get limpiar => _t('limpiar');
  String get aplicar => _t('aplicar');
  String get importeMinimo => _t('importeMinimo');
  String get importeMaximo => _t('importeMaximo');
  String get fechas => _t('fechas');
  String get elegirFechas => _t('elegirFechas');
  String get sinResultados => _t('sinResultados');

  // --- Efectivo / Tarjeta / Total ---
  String get vistaTarjeta => _t('vistaTarjeta');
  String get vistaTotal => _t('vistaTotal');
  String limiteEfectivoDe(String mes) => _formatear('limiteEfectivoDe', {'mes': mes});
  String limiteEfectivoBoton(String valor) => _formatear('limiteEfectivoBoton', {'valor': valor});
  String get sinLimiteEfectivo => _t('sinLimiteEfectivo');
  String get limiteEfectivoExplicacion => _t('limiteEfectivoExplicacion');
  String nombreMes(int mes) => _t('mes$mes');
  // --- Cuentas de ahorro ---
  String get cuentasAhorro => _t('cuentasAhorro');
  String get todasLasCuentas => _t('todasLasCuentas');
  String get anadirCuenta => _t('anadirCuenta');
  String get gestionarCuentas => _t('gestionarCuentas');
  String get nuevaCuentaAhorro => _t('nuevaCuentaAhorro');
  String get editarCuentaAhorro => _t('editarCuentaAhorro');
  String get nombreDeCuenta => _t('nombreDeCuenta');
  String get banco => _t('banco');
  String get cuentaPrincipal => _t('cuentaPrincipal');
  String get hacerPrincipal => _t('hacerPrincipal');
  String get cuentaPrincipalExplicacion => _t('cuentaPrincipalExplicacion');
  String get sinCuentasAhorro => _t('sinCuentasAhorro');
  String get cuentaAhorroCampo => _t('cuentaAhorroCampo');
  String get eliminarCuentaAviso => _t('eliminarCuentaAviso');
  String eliminarCuentaConfirmar(String cuenta) => _formatear('eliminarCuentaConfirmar', {'cuenta': cuenta});

  // --- Cuentas bancarias e IBAN ---
  String get cuentasBancarias => _t('cuentasBancarias');
  String get cuentasBancariasDescripcion => _t('cuentasBancariasDescripcion');
  String get cuentasCorrientes => _t('cuentasCorrientes');
  String get sinCuentasCorrientes => _t('sinCuentasCorrientes');
  String get nuevaCuenta => _t('nuevaCuenta');
  String get corriente => _t('corriente');
  String get ibanOpcional => _t('ibanOpcional');
  String get ibanNoValido => _t('ibanNoValido');
  String get pegar => _t('pegar');
  String get neobanco => _t('neobanco');
  String get saldoOpcional => _t('saldoOpcional');
  String get saldoActual => _t('saldoActual');
  String get actualizarSaldo => _t('actualizarSaldo');
  String cuentaDe(String banco) => _formatear('cuentaDe', {'banco': banco});

  // --- Extractos, historial y pagos detectados ---
  String get importarExtracto => _t('importarExtracto');
  String get importarExtractoAyuda => _t('importarExtractoAyuda');
  String get extractoNoValido => _t('extractoNoValido');
  String extractoImportado(int n) => _formatear('extractoImportado', {'n': '$n'});
  String actualizarSaldoA(String saldo) => _formatear('actualizarSaldoA', {'saldo': saldo});
  String movimientosExtracto(int n) => _formatear('movimientosExtracto', {'n': '$n'});
  String get elegirGastos => _t('elegirGastos');
  String get soloSaldo => _t('soloSaldo');
  String importarN(int n) => _formatear('importarN', {'n': '$n'});
  String get yaImportado => _t('yaImportado');
  String get historialSaldo => _t('historialSaldo');
  String get pagosDetectados => _t('pagosDetectados');
  String get anadirGasto => _t('anadirGasto');

  // --- Tipos de inversión e ISIN ---
  String get todasLasInversiones => _t('todasLasInversiones');
  String get tipoInversion => _t('tipoInversion');
  String get tickerOIsin => _t('tickerOIsin');
  String get nombreOpcional => _t('nombreOpcional');
  String get isinNoValido => _t('isinNoValido');
  String get isinNoResuelto => _t('isinNoResuelto');
  String nombreTipoInversion(String tipo) => _t('tipo.$tipo');

  // --- Conexión con los mercados ---
  String get conexionMercados => _t('conexionMercados');
  String get conexionMercadosDescripcion => _t('conexionMercadosDescripcion');
  String get conectarServidores => _t('conectarServidores');
  String get conectarServidoresDescripcion => _t('conectarServidoresDescripcion');
  String get claveApi => _t('claveApi');
  String get claveApiAyuda => _t('claveApiAyuda');
  String get sinClaveApi => _t('sinClaveApi');
  String get faltaClaveMercados => _t('faltaClaveMercados');
  String get usandoClavePropia => _t('usandoClavePropia');
  String get probarConexion => _t('probarConexion');
  String get conexionCorrecta => _t('conexionCorrecta');
  String get conexionFallida => _t('conexionFallida');
  String get conexionDesactivada => _t('conexionDesactivada');
  String get claveGuardada => _t('claveGuardada');

  // Conexión con los bancos (Open Banking)
  String get conexionBancos => _t('conexionBancos');
  String get conexionBancosDescripcion => _t('conexionBancosDescripcion');
  String get conexionBancosAyuda => _t('conexionBancosAyuda');
  String get proveedorBancario => _t('proveedorBancario');
  String get idAplicacion => _t('idAplicacion');
  String get clavePrivada => _t('clavePrivada');
  String get cargarArchivo => _t('cargarArchivo');
  String get urlVuelta => _t('urlVuelta');
  String get urlVueltaAyuda => _t('urlVueltaAyuda');
  String get paisBancos => _t('paisBancos');
  String get conexionBancosFallida => _t('conexionBancosFallida');
  String get conectarConBanco => _t('conectarConBanco');
  String get sincronizarBanco => _t('sincronizarBanco');
  String get desconectarBanco => _t('desconectarBanco');
  String desconectarBancoConfirmar(String cuenta) => _formatear('desconectarBancoConfirmar', {'cuenta': cuenta});
  String get desconectar => _t('desconectar');
  String get conectadaConBanco => _t('conectadaConBanco');
  String get conexionCaducada => _t('conexionCaducada');
  String get configuraConexionBancos => _t('configuraConexionBancos');
  String get configurar => _t('configurar');
  String get elegirBanco => _t('elegirBanco');
  String get buscarBanco => _t('buscarBanco');
  String get conectandoBanco => _t('conectandoBanco');
  String get autorizaEnBanco => _t('autorizaEnBanco');
  String autorizaEnBancoAyuda(String banco) => _formatear('autorizaEnBancoAyuda', {'banco': banco});
  String get direccionVuelta => _t('direccionVuelta');
  String get continuar => _t('continuar');
  String get autorizacionNoValida => _t('autorizacionNoValida');
  String elegirCuentaBanco(String cuenta) => _formatear('elegirCuentaBanco', {'cuenta': cuenta});
  String cuentaConectada(String banco) => _formatear('cuentaConectada', {'banco': banco});
  String errorBanco(String motivo) => _formatear('errorBanco', {'motivo': motivo});
  String get reconectarBanco => _t('reconectarBanco');
  String get limiteConsultasBanco => _t('limiteConsultasBanco');
  String get sinMovimientosNuevos => _t('sinMovimientosNuevos');

  // --- Moneda ---
  String get moneda => _t('moneda');
  String get monedaAviso => _t('monedaAviso');
  String nombreMoneda(String codigo) => _t('moneda$codigo');

  // --- Configuración ---
  String get configuracion => _t('configuracion');
  String get modoOscuro => _t('modoOscuro');
  String get modoOscuroDescripcion => _t('modoOscuroDescripcion');
  String get idioma => _t('idioma');
  String get idiomaApp => _t('idiomaApp');
  String get configuracionAvanzada => _t('configuracionAvanzada');
  String get configuracionAvanzadaDescripcion => _t('configuracionAvanzadaDescripcion');
  String get categoriasPersonalizadas => _t('categoriasPersonalizadas');
  String get categoriasPersonalizadasDescripcion => _t('categoriasPersonalizadasDescripcion');
  String get parametrosMensuales => _t('parametrosMensuales');
  String get nominaIngresoBase => _t('nominaIngresoBase');
  String get diaCobroNomina => _t('diaCobroNomina');
  String get gastoMensualEstimado => _t('gastoMensualEstimado');
  String get guardarMetas => _t('guardarMetas');
  String get configuracionGuardada => _t('configuracionGuardada');
  String get lecturaNotificaciones => _t('lecturaNotificaciones');

  // --- Temas ---
  String get temas => _t('temas');
  String get temasDescripcion => _t('temasDescripcion');
  String get colorAcento => _t('colorAcento');
  String get acentoBlancoNota => _t('acentoBlancoNota');
  String nombreAcento(String clave) => _t('acento.$clave');

  // --- Dónde guardar los datos (onboarding) ---
  String get dondeGuardarDatos => _t('dondeGuardarDatos');
  String get dondeGuardarDescripcion => _t('dondeGuardarDescripcion');
  String get soloEsteDispositivo => _t('soloEsteDispositivo');
  String get soloEsteDispositivoDescripcion => _t('soloEsteDispositivoDescripcion');
  String get servidorPropio => _t('servidorPropio');
  String get servidorPropioDescripcion => _t('servidorPropioDescripcion');
  String get urlServidor => _t('urlServidor');
  String get urlServidorInvalida => _t('urlServidorInvalida');
  String get sincronizacionEnDesarrollo => _t('sincronizacionEnDesarrollo');

  // --- Onboarding ---
  String get aparienciaEIdioma => _t('aparienciaEIdioma');
  String get paletaColores => _t('paletaColores');
  String get tusDatosFinancieros => _t('tusDatosFinancieros');
  String get datosFinancierosDescripcion => _t('datosFinancierosDescripcion');
  String get nominaMensual => _t('nominaMensual');
  String get presupuestoEstimado => _t('presupuestoEstimado');
  String get diaCobro => _t('diaCobro');
  String get gastosFijos => _t('gastosFijos');
  String get gastosFijosDescripcion => _t('gastosFijosDescripcion');
  String get anadirGastoFijo => _t('anadirGastoFijo');
  String get ningunGastoFijo => _t('ningunGastoFijo');

  // --- Gastos fijos ---
  String get nuevoGastoFijo => _t('nuevoGastoFijo');
  String get gastosFijosExplicacion => _t('gastosFijosExplicacion');
  String get desglosarRecibo => _t('desglosarRecibo');

  // --- Categorías ---
  String get categorias => _t('categorias');
  String get activos => _t('activos');
  String get nuevaCategoria => _t('nuevaCategoria');
  String get seleccionaIcono => _t('seleccionaIcono');

  // --- Formulario de transacción ---
  String get nuevoGasto => _t('nuevoGasto');
  String get nuevoIngreso => _t('nuevoIngreso');
  String get editarGasto => _t('editarGasto');
  String get editarIngreso => _t('editarIngreso');
  String get nuevaCompra => _t('nuevaCompra');
  String get nuevaVenta => _t('nuevaVenta');
  String get editarCompra => _t('editarCompra');
  String get editarVenta => _t('editarVenta');
  String get cuentaAfectada => _t('cuentaAfectada');
  String get tiquet => _t('tiquet');
  String get hacerFotoTiquet => _t('hacerFotoTiquet');
  String get tiquetDesdeGaleria => _t('tiquetDesdeGaleria');
  String get cambiarTiquet => _t('cambiarTiquet');
  String get quitarTiquet => _t('quitarTiquet');
  String get verTiquet => _t('verTiquet');
  String get tiquetNoEncontrado => _t('tiquetNoEncontrado');

  // --- Formulario de inversión ---
  String get cantidadTitulos => _t('cantidadTitulos');
  String get precioPorTitulo => _t('precioPorTitulo');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.esSoportado(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
