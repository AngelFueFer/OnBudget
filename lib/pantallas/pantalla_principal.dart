import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:presupuesto_familiar/base_datos/db_helper.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/app_strings.dart';
import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/visor_tiquet.dart';
import 'package:presupuesto_familiar/servicios/servicio_tiquets.dart';
import 'package:presupuesto_familiar/pantallas/formulario_transaccion.dart';
import 'package:presupuesto_familiar/pantallas/formulario_inversion.dart';
import 'package:presupuesto_familiar/pantallas/hoja_filtros.dart';
import 'package:presupuesto_familiar/pantallas/selector_vista_presupuesto.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/config_mercados.dart';
import 'package:presupuesto_familiar/utilidades/isin.dart';
import 'package:presupuesto_familiar/modelos/filtro_movimientos.dart';
import 'package:presupuesto_familiar/modelos/division_presupuesto.dart';
import 'package:presupuesto_familiar/servicios/api_bolsa.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/modelos/activo.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_configuracion.dart';
import 'package:presupuesto_familiar/utilidades/diccionario_iconos.dart';
import 'package:presupuesto_familiar/utilidades/dialogo_texto.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  final DBHelper db = DBHelper();
  final PageController _pageController = PageController(initialPage: 1);

  int _paginaActual = 1;
  final Map<String, double> _preciosEnVivo = {};
  bool _actualizandoBolsa = false;
  bool _bolsaSincronizada = false;
  bool _errorBolsa = false;

  double _metaGastoMensual = 0.0;
  double _nominaMensual = 0.0;
  int _diaCobro = 1;
  double _tasaAhorro = 0.0; // Interés anual (TAE %) que remunera el ahorro
  FiltroMovimientos _filtro = FiltroMovimientos.vacio; // Se aplica a las listas de Presupuesto y Ahorro
  VistaPresupuesto _vista = VistaPresupuesto.total; // Selector Efectivo / Tarjeta / Total del Presupuesto Mensual
  double _limiteEfectivo = 0.0; // Límite de efectivo del periodo actual (se resta de la tarjeta)
  List<CuentaAhorro> _cuentasAhorro = []; // Cuentas bancarias de ahorro (por defecto ninguna)
  String? _cuentaAhorroSeleccionada; // id de la cuenta visible en Ahorro, o _todasLasCuentas
  static const String _todasLasCuentas = '__todas__';
  String? _tipoInversionSeleccionado; // null = todas las inversiones
  FiltroMovimientos _filtroInversion = FiltroMovimientos.vacio; // Activos (por ticker) e importe de la operación
  static const String _todasLasInversiones = '__todas_inversiones__';
  static const String _accionAnadirCuenta = '__anadir__';
  static const String _accionGestionarCuentas = '__gestionar__';
  Map<String, String> _mapaNombresAIconos = {};

  @override
  void initState() {
    super.initState();
    _cargarPreferenciasEInyectarNomina();
  }

  Future<void> _cargarPreferenciasEInyectarNomina() async {
    final prefs = await SharedPreferences.getInstance();

    _metaGastoMensual = prefs.getDouble(DBKeys.gastoMensual) ?? 0.0;
    _nominaMensual = prefs.getDouble(DBKeys.nominaMensual) ?? 0.0;
    final int diaCobro = prefs.getInt(DBKeys.diaCobro) ?? 1;
    _diaCobro = diaCobro;
    _tasaAhorro = prefs.getDouble(DBKeys.tasaAhorro) ?? 0.0;
    _limiteEfectivo = _limitesEfectivo(prefs)[_clavePeriodo()] ?? 0.0;
    await _cargarCuentasAhorro();

    final ahora = DateTime.now();
    final mesActualStr = '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';
    final ultimoMesInyectado = prefs.getString(DBKeys.ultimoMesNomina) ?? '';

    int diasEnMesActual = DateTime(ahora.year, ahora.month + 1, 0).day;
    int diaCobroEfectivo = diaCobro;
    if (diaCobroEfectivo > diasEnMesActual) {
      diaCobroEfectivo = diasEnMesActual;
    }

    if (ultimoMesInyectado != mesActualStr && _nominaMensual > 0 && ahora.day >= diaCobroEfectivo) {
      // Cierre del periodo anterior: lo que sobra pasa a Ahorro y, si quedó en negativo, se cubre desde Ahorro
      if (ultimoMesInyectado.isNotEmpty) {
        await _traspasarRemanente(ultimoMesInyectado, ahora);
      }

      double montoParaAhorro = _nominaMensual - _metaGastoMensual;
      double montoParaPresupuesto = _metaGastoMensual;

      if (montoParaAhorro < 0) {
        montoParaAhorro = 0;
        montoParaPresupuesto = _nominaMensual;
      }

      if (montoParaPresupuesto > 0) {
        await db.insertarTransaccion(
          Transaccion(
            montoEnCentimos: (montoParaPresupuesto * AppNumbers.centimosEnEuro).round(),
            concepto: AppStrings.nominaPartePresupuesto,
            fecha: ahora,
            categoria: AppStrings.categoriaSalario,
            esIngreso: true,
            tarroDestino: AppStrings.cuentaMensual,
          ),
        );
      }

      if (montoParaAhorro > 0) {
        await db.insertarTransaccion(
          Transaccion(
            montoEnCentimos: (montoParaAhorro * AppNumbers.centimosEnEuro).round(),
            concepto: AppStrings.nominaParteAhorro,
            fecha: ahora,
            categoria: AppStrings.categoriaSalario,
            esIngreso: true,
            tarroDestino: AppStrings.ahorro,
            cuentaAhorro: _cuentaPrincipal?.id,
          ),
        );
      }

      final String gastosFijosJson = prefs.getString(DBKeys.gastosFijos) ?? '[]';
      final List<dynamic> listaGastosFijos = jsonDecode(gastosFijosJson);

      for (var gasto in listaGastosFijos) {
        final double montoGasto = gasto['monto'] ?? 0.0;
        if (montoGasto > 0) {
          await db.insertarTransaccion(
            Transaccion(
              montoEnCentimos: (montoGasto * AppNumbers.centimosEnEuro).round(),
              concepto: gasto['nombre'],
              fecha: ahora,
              categoria: gasto['categoria'],
              esIngreso: false,
              tarroDestino: AppStrings.cuentaMensual,
            ),
          );
        }
      }
      await prefs.setString(DBKeys.ultimoMesNomina, mesActualStr);
    }

    // Cargar los iconos personalizados
    final String? categoriasJson = prefs.getString(DBKeys.categoriasJson);
    if (categoriasJson != null) {
      final List<dynamic> decodificado = jsonDecode(categoriasJson);
      _mapaNombresAIconos = {for (var e in decodificado) e['nombre'].toString(): e['icono'].toString()};
    }

    if (mounted) setState(() {});
  }

  // Deja la Cuenta Mensual a cero entre periodos, siempre contra la cuenta de ahorro principal:
  // - saldo positivo: pasa a Ahorro como 'Remanente AAAA-MM';
  // - saldo negativo: Ahorro lo cubre como 'Déficit AAAA-MM'.
  Future<void> _traspasarRemanente(String mesCerrado, DateTime fecha) async {
    final transacciones = await db.obtenerTransaccionesPorCuenta(AppStrings.cuentaMensual);
    int saldoCentimos = 0;
    for (var t in transacciones) {
      saldoCentimos += t.esIngreso ? t.montoEnCentimos : -t.montoEnCentimos;
    }
    if (saldoCentimos == 0) return;

    final sobra = saldoCentimos > 0;
    final concepto = sobra ? AppStrings.conceptoRemanente(mesCerrado) : AppStrings.conceptoDeficit(mesCerrado);
    final categoria = sobra ? AppStrings.categoriaRemanente : AppStrings.categoriaDeficit;
    await db.insertarTransaccion(
      Transaccion(
        montoEnCentimos: saldoCentimos.abs(),
        concepto: concepto,
        fecha: fecha,
        categoria: categoria,
        esIngreso: !sobra,
        tarroDestino: AppStrings.cuentaMensual,
      ),
    );
    await db.insertarTransaccion(
      Transaccion(
        montoEnCentimos: saldoCentimos.abs(),
        concepto: concepto,
        fecha: fecha,
        categoria: categoria,
        esIngreso: sobra,
        tarroDestino: AppStrings.ahorro,
        cuentaAhorro: _cuentaPrincipal?.id,
      ),
    );
  }

  // Inicio del periodo presupuestario actual: el último día de cobro
  // --- Límite de efectivo (por periodo presupuestario) ---

  // 'AAAA-MM' del periodo actual (empieza el día de cobro)
  String _clavePeriodo() {
    final inicio = _inicioPeriodoActual();
    return '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}';
  }

  Map<String, double> _limitesEfectivo(SharedPreferences prefs) {
    final Map<String, dynamic> mapa = jsonDecode(prefs.getString(DBKeys.limitesEfectivo) ?? '{}');
    return mapa.map((clave, valor) => MapEntry(clave, (valor as num).toDouble()));
  }

  void _cambiarVista(VistaPresupuesto vista) {
    setState(() => _vista = vista);
    if (vista == VistaPresupuesto.efectivo) _pedirLimiteSiEsPrimeraVez();
  }

  // La primera vez que se entra en Efectivo en cada periodo se propone fijar el límite
  Future<void> _pedirLimiteSiEsPrimeraVez() async {
    final prefs = await SharedPreferences.getInstance();
    final periodo = _clavePeriodo();
    if (_limitesEfectivo(prefs).containsKey(periodo) || prefs.getString(DBKeys.limiteEfectivoPreguntado) == periodo) return;
    await prefs.setString(DBKeys.limiteEfectivoPreguntado, periodo);
    if (mounted) await _editarLimiteEfectivo();
  }

  Future<void> _editarLimiteEfectivo() async {
    final l10n = AppLocalizations.of(context);
    final prefs = await SharedPreferences.getInstance();
    final limites = _limitesEfectivo(prefs);
    final periodo = _clavePeriodo();
    // Propone el del periodo actual o, si no hay, el último que se usó
    final ultimoUsado = limites.isEmpty ? null : limites[(limites.keys.toList()..sort()).last];
    final propuesto = limites[periodo] ?? ultimoUsado;
    double? leer(String texto) => texto.isEmpty ? 0.0 : double.tryParse(texto.replaceAll(',', '.'));
    if (!mounted) return;

    final texto = await mostrarDialogoTexto(
      context,
      titulo: l10n.limiteEfectivoDe(l10n.nombreMes(_inicioPeriodoActual().month)),
      etiqueta: l10n.efectivo,
      valorInicial: propuesto != null && propuesto > 0 ? propuesto.toString() : '',
      sufijo: _moneda.simbolo,
      icono: Icons.payments,
      nota: l10n.limiteEfectivoExplicacion,
      teclado: const TextInputType.numberWithOptions(decimal: true),
      textoConfirmar: l10n.guardar,
      validar: (texto) async => (leer(texto) ?? -1) >= 0,
    );
    if (texto == null) return;

    final nuevo = leer(texto)!;
    limites[periodo] = nuevo;
    await prefs.setString(DBKeys.limitesEfectivo, jsonEncode(limites));
    if (mounted) setState(() => _limiteEfectivo = nuevo);
  }

  DateTime _inicioPeriodoActual() {
    final ahora = DateTime.now();
    DateTime diaCobroDelMes(int anio, int mes) {
      final diasDelMes = DateTime(anio, mes + 1, 0).day;
      return DateTime(anio, mes, _diaCobro > diasDelMes ? diasDelMes : _diaCobro);
    }

    final cobroEsteMes = diaCobroDelMes(ahora.year, ahora.month);
    return ahora.isBefore(cobroEsteMes) ? diaCobroDelMes(ahora.year, ahora.month - 1) : cobroEsteMes;
  }

  // --- Cuentas de ahorro ---

  CuentaAhorro? get _cuentaPrincipal => _cuentasAhorro.where((c) => c.principal).firstOrNull ?? _cuentasAhorro.firstOrNull;

  // Cuenta concreta visible en Ahorro (null si no hay cuentas o se ven todas)
  CuentaAhorro? get _cuentaSeleccionada => _cuentasAhorro.where((c) => c.id == _cuentaAhorroSeleccionada).firstOrNull;

  bool get _verTodasLasCuentas => _cuentaAhorroSeleccionada == _todasLasCuentas && _cuentasAhorro.length > 1;

  Future<void> _cargarCuentasAhorro({String? seleccionar}) async {
    _cuentasAhorro = await ServicioCuentasAhorro.cargar();
    if (seleccionar != null) _cuentaAhorroSeleccionada = seleccionar;
    // Si la seleccionada ya no existe, se vuelve a la principal
    if (!_verTodasLasCuentas && _cuentaSeleccionada == null) _cuentaAhorroSeleccionada = _cuentaPrincipal?.id;
    if (mounted) setState(() {});
  }

  // Movimientos sin cuenta (anteriores a crear la primera) se consideran de la principal
  String? _cuentaDe(Transaccion t) => t.cuentaAhorro ?? _cuentaPrincipal?.id;

  List<Transaccion> _movimientosDeCuentaSeleccionada(List<Transaccion> movimientos) {
    final seleccionada = _cuentaSeleccionada;
    if (seleccionada == null || _verTodasLasCuentas) return movimientos;
    return movimientos.where((t) => _cuentaDe(t) == seleccionada.id).toList();
  }

  Future<void> _elegirCuentaAhorro(String valor) async {
    if (valor == _accionAnadirCuenta) {
      final nueva = await mostrarDialogoCuentaAhorro(context);
      if (nueva != null) await _cargarCuentasAhorro(seleccionar: nueva.id);
    } else if (valor == _accionGestionarCuentas) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaCuentasAhorro()));
      await _cargarCuentasAhorro();
    } else {
      setState(() => _cuentaAhorroSeleccionada = valor);
    }
  }

  // Menú desplegable de cuentas de ahorro (o botón para añadir la primera)
  Widget _construirSelectorCuentaAhorro(AppLocalizations l10n, Color colorTema) {
    if (_cuentasAhorro.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppNumbers.altoSelectorBarra / 2),
        onTap: () => _elegirCuentaAhorro(_accionAnadirCuenta),
        child: _pildoraDesplegable(icono: Icons.add, texto: l10n.anadirCuenta, color: colorTema, conFlecha: false),
      );
    }

    final seleccionada = _verTodasLasCuentas ? null : _cuentaSeleccionada;
    return PopupMenuButton<String>(
      tooltip: l10n.cuentasAhorro,
      onSelected: _elegirCuentaAhorro,
      itemBuilder: (context) => [
        if (_cuentasAhorro.length > 1)
          PopupMenuItem(
            value: _todasLasCuentas,
            child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.account_balance_wallet), title: Text(l10n.todasLasCuentas)),
          ),
        ..._cuentasAhorro.map(
          (cuenta) => PopupMenuItem(
            value: cuenta.id,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(cuenta.principal ? Icons.star : Icons.savings, color: colorTema),
              title: Text(cuenta.nombre),
              subtitle: cuenta.banco.isEmpty ? null : Text(cuenta.banco),
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _accionAnadirCuenta,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.add), title: Text(l10n.anadirCuenta)),
        ),
        PopupMenuItem(
          value: _accionGestionarCuentas,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.settings), title: Text(l10n.gestionarCuentas)),
        ),
      ],
      child: _pildoraDesplegable(
        icono: seleccionada == null ? Icons.account_balance_wallet : (seleccionada.principal ? Icons.star : Icons.savings),
        texto: seleccionada?.nombreCompleto ?? l10n.todasLasCuentas,
        color: colorTema,
      ),
    );
  }

  // Mismo tamaño para los tres selectores centrados de la barra superior
  Widget _marcoSelector(Widget selector) {
    return SizedBox(
      width: AppNumbers.anchoSelectorBarra,
      height: AppNumbers.altoSelectorBarra,
      child: Center(child: selector),
    );
  }

  // Aspecto común de los desplegables centrados de la barra superior (mismo borde redondeado que el selector de Presupuesto)
  Widget _pildoraDesplegable({required IconData icono, required String texto, required Color color, bool conFlecha = true}) {
    return Container(
      width: AppNumbers.anchoSelectorBarra,
      height: AppNumbers.altoSelectorBarra,
      padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingMedio),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(AppNumbers.altoSelectorBarra / 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(texto, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
          ),
          if (conFlecha) Icon(Icons.arrow_drop_down, color: color),
        ],
      ),
    );
  }

  // --- Tipos de inversión ---

  // Desplegable centrado de Inversión: todas o un tipo concreto
  Widget _construirSelectorTipoInversion(AppLocalizations l10n) {
    final tipo = _tipoInversionSeleccionado;
    return PopupMenuButton<String>(
      tooltip: l10n.tipoInversion,
      onSelected: (valor) => setState(() => _tipoInversionSeleccionado = valor == _todasLasInversiones ? null : valor),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _todasLasInversiones,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.dashboard), title: Text(l10n.todasLasInversiones)),
        ),
        const PopupMenuDivider(),
        ...AppStrings.tiposInversion.map(
          (t) => PopupMenuItem(
            value: t,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(iconosTipoInversion[t], color: Theme.of(context).colorScheme.onSurfaceVariant),
              title: Text(l10n.nombreTipoInversion(t)),
            ),
          ),
        ),
      ],
      child: _pildoraDesplegable(
        icono: tipo == null ? Icons.dashboard : iconosTipoInversion[tipo]!,
        texto: tipo == null ? l10n.todasLasInversiones : l10n.nombreTipoInversion(tipo),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _mostrarDialogoTasaAhorro() async {
    final l10n = AppLocalizations.of(context);
    double? leerTasa(String texto) => texto.isEmpty ? 0.0 : double.tryParse(texto.replaceAll(',', '.'));

    final texto = await mostrarDialogoTexto(
      context,
      titulo: l10n.remuneracionAhorro,
      etiqueta: l10n.tasaAnual,
      valorInicial: _tasaActual > 0 ? _tasaActual.toString() : '',
      sufijo: '%',
      nota: l10n.remuneracionExplicacion,
      teclado: const TextInputType.numberWithOptions(decimal: true),
      textoConfirmar: l10n.guardar,
      validar: (texto) async => (leerTasa(texto) ?? -1) >= 0, // Vacío = sin remuneración
    );
    if (texto == null) return;

    final nuevaTasa = leerTasa(texto)!;
    final cuenta = _cuentaSeleccionada;
    if (cuenta != null) {
      // Cada cuenta de ahorro tiene su propio interés
      await ServicioCuentasAhorro.editar(cuenta.id, tasa: nuevaTasa);
      await _cargarCuentasAhorro();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(DBKeys.tasaAhorro, nuevaTasa);
      if (mounted) setState(() => _tasaAhorro = nuevaTasa);
    }
  }

  // Interés de la cuenta visible (o el general si aún no hay cuentas)
  double get _tasaActual => _cuentaSeleccionada?.tasa ?? _tasaAhorro;

  Future<List<Transaccion>> _obtenerDatosPorCuenta(String nombreCuenta) async {
    return await db.obtenerTransaccionesPorCuenta(nombreCuenta);
  }

  Future<List<ActivoFinanciero>> _obtenerDatosInversion() async {
    return await db.obtenerActivos();
  }

  Future<void> _sincronizarBolsaAutomaticamente() async {
    if (!ConfigMercados.conectada) return; // Conexión desactivada o sin clave del usuario
    setState(() {
      _actualizandoBolsa = true;
      _errorBolsa = false;
    });

    var activos = await _obtenerDatosInversion();
    // ISIN guardados sin ticker (sin conexión o sin clave de API): se intenta resolverlos de nuevo
    final resueltos = <String, String?>{};
    for (final a in activos.where((a) => a.isin != null && Isin.pareceIsin(a.ticker))) {
      final ticker = resueltos.containsKey(a.isin) ? resueltos[a.isin] : (resueltos[a.isin!] = await ApiBolsa.buscarTickerPorIsin(a.isin!));
      if (ticker != null) await db.actualizarActivo(a.copiarConTicker(ticker));
    }
    if (resueltos.values.any((t) => t != null)) activos = await _obtenerDatosInversion();
    final tickersUnicos = activos.map((a) => a.ticker).where((t) => !Isin.pareceIsin(t)).toSet();
    bool huboFallos = false;

    for (String ticker in tickersUnicos) {
      final precio = await ApiBolsa.obtenerPrecioActual(ticker);
      if (precio != null) {
        _preciosEnVivo[ticker] = precio;
      } else {
        huboFallos = true;
      }
    }

    if (mounted) {
      setState(() {
        _actualizandoBolsa = false;
        _bolsaSincronizada = true;
        _errorBolsa = huboFallos;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: AppNumbers.alturaBarraSuperior,
        // Filtro en las tres pestañas (en Inversión filtra por activo e importe)
        leading: IconButton(
          tooltip: l10n.filtrar,
          onPressed: _abrirFiltros,
          icon: Badge(
            isLabelVisible: _filtroVisible.activo,
            label: Text('${_filtroVisible.criteriosActivos}'),
            child: Icon(_filtroVisible.activo ? Icons.filter_alt : Icons.filter_alt_outlined),
          ),
        ),
        centerTitle: true,
        // Centrado arriba, todos con el mismo tamaño: tipo de inversión, Tarjeta / Total / Efectivo y cuentas de ahorro
        title: _marcoSelector(switch (_paginaActual) {
          0 => _construirSelectorTipoInversion(l10n),
          1 => SelectorVistaPresupuesto(vista: _vista, onCambio: _cambiarVista),
          _ => _construirSelectorCuentaAhorro(l10n, Theme.of(context).colorScheme.onSurfaceVariant),
        }),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: AppLocalizations.of(context).configuracion,
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PantallaConfiguracion())).then((_) {
                _cargarPreferenciasEInyectarNomina();
                setState(() => _bolsaSincronizada = false);
                if (_paginaActual == 0) _sincronizarBolsaAutomaticamente();
              });
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _paginaActual = index);
          if (index == 0 && !_bolsaSincronizada && !_actualizandoBolsa) {
            _sincronizarBolsaAutomaticamente();
          }
        },
        children: [
          _construirVistaInversion(),
          _construirVistaCuenta(AppStrings.cuentaMensual, l10n.tituloPresupuestoMensual, Theme.of(context).colorScheme.onSurfaceVariant),
          _construirVistaCuenta(AppStrings.ahorro, l10n.ahorro, Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ),
      // − a la izquierda (gasto / venta) y + a la derecha (ingreso / compra), mismos colores en todas las pestañas.
      // Van en una franja fija bajo la lista, así los movimientos no pasan por debajo de los botones.
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            sizeConstraints: BoxConstraints.tightFor(width: AppNumbers.tamanoBotonFlotante, height: AppNumbers.tamanoBotonFlotante),
            iconSize: AppNumbers.tamanoIconoBotonFlotante,
            foregroundColor: Colors.white,
          ),
        ),
        // Deslizar sobre la franja también cambia de pestaña, igual que sobre la lista
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _arrastrarFranja,
          onHorizontalDragEnd: _soltarFranja,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(AppNumbers.paddingStandard, AppNumbers.paddingCorto, AppNumbers.paddingStandard, AppNumbers.paddingStandard),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  heroTag: 'botonMenos',
                  tooltip: _paginaActual == 0 ? l10n.nuevaVenta : l10n.nuevoGasto,
                  backgroundColor: AppColors.saldoNegativo,
                  onPressed: () => _abrirNuevoMovimiento(esPositivo: false),
                  child: const Icon(Icons.remove),
                ),
                FloatingActionButton(
                  heroTag: 'botonMas',
                  tooltip: _paginaActual == 0 ? l10n.nuevaCompra : l10n.nuevoIngreso,
                  backgroundColor: AppColors.saldoPositivo,
                  onPressed: () => _abrirNuevoMovimiento(esPositivo: true),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // La franja de los botones mueve las pestañas siguiendo el dedo...
  void _arrastrarFranja(DragUpdateDetails detalles) {
    if (!_pageController.hasClients) return;
    final posicion = _pageController.position;
    posicion.jumpTo((posicion.pixels - detalles.delta.dx).clamp(posicion.minScrollExtent, posicion.maxScrollExtent));
  }

  // ...y al soltar encaja en la más cercana (o en la siguiente si el gesto fue rápido)
  void _soltarFranja(DragEndDetails detalles) {
    if (!_pageController.hasClients) return;
    final pagina = _pageController.page ?? _paginaActual.toDouble();
    final velocidad = detalles.primaryVelocity ?? 0;
    final destino = switch (velocidad) {
      < -AppNumbers.velocidadCambioPestana => pagina.floor() + 1,
      > AppNumbers.velocidadCambioPestana => pagina.ceil() - 1,
      _ => pagina.round(),
    };
    _pageController.animateToPage(destino.clamp(0, 2), duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // --- Filtro de movimientos ---

  // Filtro de la pestaña visible
  FiltroMovimientos get _filtroVisible => _paginaActual == 0 ? _filtroInversion : _filtro;

  Future<void> _abrirFiltros() async {
    final l10n = AppLocalizations.of(context);
    if (_paginaActual == 0) return _abrirFiltrosInversion(l10n);
    final cuenta = _paginaActual == 2 ? AppStrings.ahorro : AppStrings.cuentaMensual;

    // Categorías que aparecen en la cuenta visible (más las ya filtradas), por nombre visible
    final transacciones = await db.obtenerTransaccionesPorCuenta(cuenta);
    final categorias = {...transacciones.map((t) => t.categoria), ..._filtro.categorias}.toList()
      ..sort((a, b) => l10n.nombreCategoria(a).toLowerCase().compareTo(l10n.nombreCategoria(b).toLowerCase()));
    if (!mounted) return;

    final nuevo = await mostrarHojaFiltros(context, filtroActual: _filtro, categoriasDisponibles: categorias);
    if (nuevo != null && mounted) setState(() => _filtro = nuevo);
  }

  // En Inversión las "categorías" son los activos (por ticker, con su nombre visible) y no hay fechas
  Future<void> _abrirFiltrosInversion(AppLocalizations l10n) async {
    final activos = await db.obtenerActivos();
    final nombres = {for (final a in activos) a.ticker: a.nombreVisible};
    final tickers = {...nombres.keys, ..._filtroInversion.categorias}.toList()
      ..sort((a, b) => (nombres[a] ?? a).toLowerCase().compareTo((nombres[b] ?? b).toLowerCase()));
    if (!mounted) return;

    final nuevo = await mostrarHojaFiltros(
      context,
      filtroActual: _filtroInversion,
      categoriasDisponibles: tickers,
      nombreCategoria: (ticker) => nombres[ticker] ?? ticker,
      tituloCategorias: l10n.activos,
      conFechas: false,
    );
    if (nuevo != null && mounted) setState(() => _filtroInversion = nuevo);
  }

  // Al tocar una categoría de la barra del presupuesto; tocarla otra vez quita el filtro
  void _filtrarPorCategoria(String categoria) {
    setState(() {
      final yaFiltrada = _filtro.categorias.length == 1 && _filtro.categorias.contains(categoria);
      _filtro = yaFiltrada
          ? _filtro.sinCategorias()
          : FiltroMovimientos(categorias: {categoria}, importeMinimo: _filtro.importeMinimo, importeMaximo: _filtro.importeMaximo, fechas: _filtro.fechas);
    });
  }

  // Chips con los criterios activos; cada uno se puede quitar por separado
  Widget _construirFiltrosActivos(AppLocalizations l10n) => _chipsFiltro(l10n, _filtro, (nuevo) => setState(() => _filtro = nuevo), l10n.nombreCategoria);

  Widget _chipsFiltro(AppLocalizations l10n, FiltroMovimientos filtro, ValueChanged<FiltroMovimientos> cambiar, String Function(String) nombre) {
    final chips = <Widget>[];

    if (filtro.filtraCategorias) {
      chips.add(
        InputChip(
          avatar: const Icon(Icons.category, size: 18),
          label: Text(filtro.categorias.map(nombre).join(', ')),
          onDeleted: () => cambiar(filtro.sinCategorias()),
        ),
      );
    }
    if (filtro.filtraImporte) {
      final minimo = filtro.importeMinimo;
      final maximo = filtro.importeMaximo;
      final texto = minimo != null && maximo != null
          ? '${_moneda.formatear(minimo)} – ${_moneda.formatear(maximo)}'
          : minimo != null
          ? '≥ ${_moneda.formatear(minimo)}'
          : '≤ ${_moneda.formatear(maximo!)}';
      chips.add(InputChip(avatar: const Icon(Icons.euro, size: 18), label: Text(texto), onDeleted: () => cambiar(filtro.sinImporte())));
    }
    if (filtro.filtraFechas) {
      chips.add(
        InputChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(formatearRangoFechas(context, filtro.fechas!)),
          onDeleted: () => cambiar(filtro.sinFechas()),
        ),
      );
    }
    chips.add(ActionChip(label: Text(l10n.limpiar), onPressed: () => cambiar(FiltroMovimientos.vacio)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppNumbers.paddingStandard, AppNumbers.paddingCorto, AppNumbers.paddingStandard, 0),
      child: Wrap(spacing: AppNumbers.paddingCorto, runSpacing: 4, children: chips),
    );
  }

  // Método de pago con el que se abre un gasto nuevo según la vista del Presupuesto Mensual
  String? get _metodoPagoDeLaVista {
    if (_paginaActual != 1) return null;
    switch (_vista) {
      case VistaPresupuesto.efectivo:
        return AppStrings.metodoEfectivo;
      case VistaPresupuesto.tarjeta:
        return AppStrings.metodoTarjeta;
      case VistaPresupuesto.total:
        return null;
    }
  }

  // En Inversión: + compra / − venta. En las cuentas: + ingreso / − gasto.
  void _abrirNuevoMovimiento({required bool esPositivo}) {
    if (_paginaActual == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FormularioInversion(esCompra: esPositivo, tipoPredefinido: _tipoInversionSeleccionado),
        ),
      ).then((_) {
        setState(() => _bolsaSincronizada = false);
        _sincronizarBolsaAutomaticamente();
      });
    } else {
      // Desde la pestaña de Ahorro, el movimiento va por defecto a Ahorro
      final cuenta = _paginaActual == 2 ? AppStrings.ahorro : AppStrings.cuentaMensual;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FormularioTransaccion(
            esIngreso: esPositivo,
            cuentaPredefinida: cuenta,
            metodoPagoPredefinido: _metodoPagoDeLaVista,
            // Desde Ahorro, en la cuenta bancaria que se está viendo (o la principal con "Todas")
            cuentaAhorroPredefinida: _paginaActual == 2 ? (_verTodasLasCuentas ? _cuentaPrincipal : _cuentaSeleccionada)?.id : null,
          ),
        ),
      ).then((_) => setState(() {}));
    }
  }

  Widget _construirBarraGastos(Map<String, double> gastos, double totalGastado, double meta) {
    if (meta <= 0) return const SizedBox();

    final l10n = AppLocalizations.of(context);
    double capacidadBarra = meta > totalGastado ? meta : totalGastado;
    double remanente = meta - totalGastado;

    return Column(
      children: [
        Container(
          height: AppNumbers.alturaBarra,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingLargo, vertical: AppNumbers.paddingCorto),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppNumbers.radiusStandard), color: Colors.transparent),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppNumbers.radiusStandard),
            child: Row(
              children: [
                ...gastos.entries.map((e) {
                  final flex = ((e.value / capacidadBarra) * AppNumbers.flexMultiplier).toInt();
                  if (flex <= 0) return const SizedBox();
                  return Expanded(
                    flex: flex,
                    child: GestureDetector(
                      onTap: () => _filtrarPorCategoria(e.key),
                      child: Container(color: AppColors.obtenerColorCategoria(e.key)),
                    ),
                  );
                }),
                if (remanente > 0)
                  Expanded(
                    flex: ((remanente / capacidadBarra) * AppNumbers.flexMultiplier).toInt(),
                    child: Container(color: Colors.grey.withValues(alpha: AppNumbers.opacityMedia)),
                  ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: AppNumbers.paddingMedio,
          alignment: WrapAlignment.center,
          // La leyenda también filtra (la barra es fina para tocarla con precisión)
          children: gastos.entries.map((e) {
            final filtrada = _filtro.categorias.contains(e.key);
            return InkWell(
              onTap: () => _filtrarPorCategoria(e.key),
              borderRadius: BorderRadius.circular(AppNumbers.radiusStandard),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, color: AppColors.obtenerColorCategoria(e.key)),
                    const SizedBox(width: 4),
                    Text(
                      '${l10n.nombreCategoria(e.key)} ${_moneda.formatear(e.value, decimales: 0)}',
                      style: TextStyle(
                        fontSize: AppNumbers.fontSizePequeno,
                        fontWeight: filtrada ? FontWeight.bold : FontWeight.normal,
                        decoration: filtrada ? TextDecoration.underline : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppNumbers.paddingCorto),
        Text(
          l10n.resumenPresupuesto(_moneda.formatear(totalGastado, decimales: 0), _moneda.formatear(meta, decimales: 0)),
          style: TextStyle(fontSize: AppNumbers.fontSizePequeno, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  IconData _obtenerIconoPara(String nombreCategoria) {
    // 1. Primero intenta buscar si le has asignado un icono personalizado en los ajustes
    String? claveIcono = _mapaNombresAIconos[nombreCategoria];

    // 2. Traductor de emergencia: si la memoria falla o es una categoría antigua, lo deduce por el nombre
    if (claveIcono == null) {
      switch (nombreCategoria.toLowerCase()) {
        case 'transporte':
          claveIcono = 'transporte';
          break;
        case 'supermercado':
          claveIcono = 'supermercado';
          break;
        case 'restaurantes':
          claveIcono = 'restaurantes';
          break;
        case 'hogar':
          claveIcono = 'hogar';
          break;
        case 'ropa':
          claveIcono = 'ropa';
          break;
        case 'teléfono':
        case 'telefono':
          claveIcono = 'telefono';
          break;
        case 'luz':
          claveIcono = 'luz';
          break;
        case 'agua':
          claveIcono = 'agua';
          break;
        case 'ocio':
          claveIcono = 'ocio';
          break;
        case 'salario':
          claveIcono = 'salario';
          break;
        case 'remanente':
          claveIcono = 'ahorro';
          break;
        default:
          claveIcono = 'general';
          break;
      }
    }

    // 3. Devuelve el icono gráfico exacto, o una etiqueta si no lo encuentra en el diccionario
    return mapaIconos[claveIcono] ?? Icons.label;
  }

  Moneda get _moneda => Moneda.of(context);

  // 'Supermercado · Visa BBVA' / 'Supermercado · Efectivo'
  String _subtituloTransaccion(AppLocalizations l10n, Transaccion t) {
    final categoria = l10n.nombreCategoria(t.categoria);
    if (t.metodoPago == AppStrings.metodoTarjeta && t.tarjeta != null) return '$categoria · ${t.tarjeta}';
    if (t.metodoPago == AppStrings.metodoEfectivo) return '$categoria · ${l10n.efectivo}';
    return categoria;
  }

  // Botón circular de acceso rápido (categorías y últimas compras de bolsa)
  Widget _construirBotonRapido({required Color colorTema, required String etiqueta, required Widget contenido, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppNumbers.anchoBotonCategoria,
        margin: const EdgeInsets.only(right: AppNumbers.paddingCorto),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: AppNumbers.radiusIconoCategoria,
              backgroundColor: colorTema.withValues(alpha: AppNumbers.opacityMedia),
              child: contenido,
            ),
            const SizedBox(height: 6),
            Text(
              etiqueta,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppNumbers.fontSizePequeno),
            ),
          ],
        ),
      ),
    );
  }

  // Menú de remuneración del ahorro: interés anual y estimación de lo que genera
  Widget _construirTarjetaRemuneracion(double saldo, Color colorTema, List<Transaccion> movimientosAhorro) {
    final l10n = AppLocalizations.of(context);
    final verTodas = _verTodasLasCuentas;
    final tasa = _tasaActual;
    double interesAnual;
    if (verTodas) {
      // Suma lo que genera cada cuenta con su propio interés
      interesAnual = 0;
      for (final cuenta in _cuentasAhorro) {
        double saldoCuenta = 0;
        for (final t in movimientosAhorro.where((t) => _cuentaDe(t) == cuenta.id)) {
          saldoCuenta += (t.esIngreso ? 1 : -1) * t.montoEnCentimos / AppNumbers.centimosEnEuro;
        }
        if (saldoCuenta > 0) interesAnual += saldoCuenta * cuenta.tasa / 100;
      }
    } else {
      interesAnual = saldo > 0 ? saldo * tasa / 100 : 0.0;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingStandard),
      child: Card(
        elevation: 0,
        color: colorTema.withValues(alpha: AppNumbers.opacityMedia),
        child: ListTile(
          // Con "Todas las cuentas" solo se muestra la estimación; el interés se edita en cada cuenta
          onTap: verTodas ? null : _mostrarDialogoTasaAhorro,
          leading: Icon(Icons.percent, color: colorTema),
          title: Text(l10n.remuneracionAhorro, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            verTodas
                ? l10n.interesEstimado(_moneda.formatear(interesAnual / 12), _moneda.formatear(interesAnual))
                : tasa > 0
                ? '${l10n.tasaAnualCorta(tasa.toStringAsFixed(2))}\n'
                      '${l10n.interesEstimado(_moneda.formatear(interesAnual / 12), _moneda.formatear(interesAnual))}'
                : l10n.sinRemuneracion,
          ),
          isThreeLine: !verTodas && tasa > 0,
          trailing: verTodas ? null : Icon(Icons.edit, color: colorTema),
        ),
      ),
    );
  }

  Widget _construirVistaCuenta(String idBaseDatos, String tituloPantalla, Color colorTema) {
    final l10n = AppLocalizations.of(context);

    return FutureBuilder<List<Transaccion>>(
      future: _obtenerDatosPorCuenta(idBaseDatos),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        // Efectivo / Tarjeta / Total solo en el Presupuesto Mensual; Ahorro siempre es el total
        final esMensual = idBaseDatos == AppStrings.cuentaMensual;
        final vista = esMensual ? _vista : VistaPresupuesto.total;
        final todos = snapshot.data ?? [];
        final division = DivisionPresupuesto.calcular(
          // En Ahorro, solo la cuenta bancaria elegida en el desplegable
          transacciones: esMensual ? todos : _movimientosDeCuentaSeleccionada(todos),
          vista: vista,
          metaMensual: _metaGastoMensual,
          limiteEfectivo: esMensual ? _limiteEfectivo : 0,
          inicioPeriodo: _inicioPeriodoActual(),
        );
        final saldo = division.saldo;
        // El saldo y la barra no dependen del filtro; el filtro solo afecta a la lista
        final visibles = division.movimientos.where(_filtro.cumple).toList();

        return FutureBuilder<List<String>>(
          future: db.obtenerTopCategorias(),
          builder: (context, snapshotTop) {
            List<String> top8 = snapshotTop.data ?? [];
            for (var def in AppStrings.categoriasDefecto) {
              if (top8.length >= AppNumbers.maxCategoriasDefault) break;
              if (!top8.contains(def)) top8.add(def);
            }

            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: AppNumbers.paddingStandard),
                  child: Column(
                    children: [
                      Text(
                        tituloPantalla,
                        style: TextStyle(
                          fontSize: AppNumbers.fontSizeTitulo,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppNumbers.paddingCorto),
                      Text(
                        _moneda.formatear(saldo),
                        style: const TextStyle(fontSize: AppNumbers.fontSizeSaldo, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppNumbers.paddingStandard),
                      if (esMensual && vista == VistaPresupuesto.efectivo) ...[
                        ActionChip(
                          avatar: const Icon(Icons.edit, size: 18),
                          label: Text(_limiteEfectivo > 0 ? l10n.limiteEfectivoBoton(_moneda.formatear(_limiteEfectivo)) : l10n.sinLimiteEfectivo),
                          onPressed: _editarLimiteEfectivo,
                        ),
                        const SizedBox(height: AppNumbers.paddingCorto),
                      ],
                      if (esMensual) _construirBarraGastos(division.gastosPorCategoria, division.totalGastado, division.meta),

                      const SizedBox(height: AppNumbers.paddingStandard),
                      if (idBaseDatos == AppStrings.ahorro)
                        _construirTarjetaRemuneracion(saldo, colorTema, todos)
                      else
                        SizedBox(
                          height: AppNumbers.altoBotonCategoria,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: top8.length,
                            padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingStandard),
                            itemBuilder: (context, index) {
                              final cat = top8[index];
                              return _construirBotonRapido(
                                colorTema: colorTema,
                                etiqueta: l10n.nombreCategoria(cat),
                                contenido: Icon(_obtenerIconoPara(cat), color: colorTema, size: AppNumbers.tamanoIconoCategoria),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FormularioTransaccion(categoriaPredefinida: cat, metodoPagoPredefinido: _metodoPagoDeLaVista),
                                    ),
                                  ).then((_) => setState(() {}));
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (_filtro.activo) _construirFiltrosActivos(l10n),
                Expanded(
                  child: visibles.isEmpty && _filtro.activo
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppNumbers.paddingLargo),
                            child: Text(
                              l10n.sinResultados,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: visibles.length,
                          itemBuilder: (context, index) {
                            final t = visibles[index];
                            final importe = _moneda.formatear(t.montoEnCentimos / AppNumbers.centimosEnEuro);
                            return Slidable(
                              key: ValueKey(t.id),
                              endActionPane: ActionPane(
                                motion: const ScrollMotion(),
                                children: [
                                  SlidableAction(
                                    onPressed: (context) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => FormularioTransaccion(transaccionAEditar: t)),
                                      ).then((_) => setState(() {}));
                                    },
                                    backgroundColor: AppColors.info,
                                    foregroundColor: Colors.white,
                                    icon: Icons.edit,
                                    label: l10n.editar,
                                  ),
                                  SlidableAction(
                                    onPressed: (context) async {
                                      if (t.id != null) {
                                        await db.eliminarTransaccion(t.id!);
                                        await ServicioTiquets.borrar(t.tiquet);
                                        setState(() {});
                                      }
                                    },
                                    backgroundColor: AppColors.error,
                                    foregroundColor: Colors.white,
                                    icon: Icons.delete,
                                    label: l10n.borrar,
                                  ),
                                ],
                              ),
                              child: ListTile(
                                leading: Icon(_obtenerIconoPara(t.categoria), color: Theme.of(context).colorScheme.onSurfaceVariant),
                                title: Text(l10n.concepto(t.concepto)),
                                subtitle: Text(_subtituloTransaccion(l10n, t)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (t.tiquet != null)
                                      IconButton(
                                        icon: const Icon(Icons.receipt_long, size: 20),
                                        tooltip: l10n.verTiquet,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => abrirTiquet(context, t.tiquet!),
                                      ),
                                    Text(
                                      '${t.esIngreso ? '+' : '-'}$importe',
                                      style: TextStyle(color: t.esIngreso ? AppColors.saldoPositivo : AppColors.saldoNegativo, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _construirVistaInversion() {
    final l10n = AppLocalizations.of(context);

    return FutureBuilder<List<ActivoFinanciero>>(
      future: _obtenerDatosInversion(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        double valorTotalInvertido = 0;
        double valorActualMercado = 0;
        final activos = (snapshot.data ?? []).where((a) => _tipoInversionSeleccionado == null || a.tipoEfectivo == _tipoInversionSeleccionado).toList();

        for (var a in activos) {
          valorTotalInvertido += (a.cantidad * a.precioCompra);
          double precioMercado = _preciosEnVivo[a.ticker] ?? a.precioCompra;
          valorActualMercado += (a.cantidad * precioMercado);
        }

        final activosVisibles = activos.where((a) => _filtroInversion.cumpleCategoriaEImporte(a.ticker, (a.cantidad * a.precioCompra).abs())).toList();
        final nombresActivos = {for (final a in activos) a.ticker: a.nombreVisible};

        final beneficio = valorActualMercado - valorTotalInvertido;
        final porcentaje = valorTotalInvertido > 0 ? beneficio / valorTotalInvertido * 100 : 0.0;
        final signo = beneficio >= 0 ? '+' : '';

        // Últimos activos comprados (sin repetir ticker), del más reciente al más antiguo
        final ultimasCompras = <ActivoFinanciero>[];
        for (var a in activos) {
          if (ultimasCompras.length >= AppNumbers.maxCategoriasDefault) break;
          if (a.cantidad > 0 && !ultimasCompras.any((u) => u.ticker == a.ticker)) ultimasCompras.add(a);
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: AppNumbers.paddingStandard),
              child: Column(
                children: [
                  Text(
                    l10n.inversion,
                    style: TextStyle(fontSize: AppNumbers.fontSizeTitulo, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppNumbers.paddingCorto),
                  Text(
                    _moneda.formatear(valorActualMercado),
                    style: const TextStyle(fontSize: AppNumbers.fontSizeSaldo, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppNumbers.paddingCorto),
                  Text(
                    l10n.rentabilidad(_moneda.formatear(beneficio, conSigno: true), '$signo${porcentaje.toStringAsFixed(2)}'),
                    style: TextStyle(
                      color: beneficio >= 0 ? AppColors.saldoPositivo : AppColors.saldoNegativo,
                      fontWeight: FontWeight.bold,
                      fontSize: AppNumbers.fontSizeSubtitulo,
                    ),
                  ),
                  const SizedBox(height: AppNumbers.paddingCorto),
                  if (!ConfigMercados.conectada)
                    Text(ConfigMercados.activa ? l10n.faltaClaveMercados : l10n.conexionDesactivada, style: TextStyle(fontSize: AppNumbers.fontSizeDetalle, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (_actualizandoBolsa) Text(l10n.sincronizandoBolsa, style: const TextStyle(fontSize: AppNumbers.fontSizeDetalle, color: AppColors.info)),
                  if (_errorBolsa) Text(l10n.errorConexion, style: const TextStyle(fontSize: AppNumbers.fontSizeDetalle, color: AppColors.error)),
                  if (ultimasCompras.isNotEmpty) ...[
                    const SizedBox(height: AppNumbers.paddingMedio),
                    Text(
                      l10n.ultimasCompras,
                      style: TextStyle(fontSize: AppNumbers.fontSizePequeno, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: AppNumbers.altoBotonCategoria,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: ultimasCompras.length,
                        padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingStandard),
                        itemBuilder: (context, index) {
                          final activo = ultimasCompras[index];
                          final simbolo = activo.ticker.split('.').first;
                          return _construirBotonRapido(
                            colorTema: Theme.of(context).colorScheme.onSurfaceVariant,
                            etiqueta: activo.nombreVisible,
                            // ISIN sin ticker: el icono de su tipo en lugar de las letras del ticker
                            contenido: Isin.pareceIsin(activo.ticker)
                                ? Icon(iconosTipoInversion[activo.tipoEfectivo], color: Theme.of(context).colorScheme.onSurfaceVariant)
                                : Text(
                                    simbolo.length > 4 ? simbolo.substring(0, 4) : simbolo,
                                    style: TextStyle(
                                      fontSize: AppNumbers.fontSizePequeno,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FormularioInversion(activoBase: activo, precioPredefinido: _preciosEnVivo[activo.ticker]),
                                ),
                              ).then((_) {
                                setState(() => _bolsaSincronizada = false);
                                _sincronizarBolsaAutomaticamente();
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_filtroInversion.activo)
              _chipsFiltro(l10n, _filtroInversion, (nuevo) => setState(() => _filtroInversion = nuevo), (t) => nombresActivos[t] ?? t),
            Expanded(
              child: ListView.builder(
                itemCount: activosVisibles.length,
                itemBuilder: (context, index) {
                  final a = activosVisibles[index];
                  final esCompra = a.cantidad > 0;
                  final precioMercado = _preciosEnVivo[a.ticker] ?? a.precioCompra;
                  final valorActualOperacion = (a.cantidad * precioMercado).abs();

                  return Slidable(
                    key: ValueKey(a.id),
                    endActionPane: ActionPane(
                      motion: const ScrollMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (context) {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => FormularioInversion(activoAEditar: a))).then((_) {
                              setState(() => _bolsaSincronizada = false);
                              _sincronizarBolsaAutomaticamente();
                            });
                          },
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          icon: Icons.edit,
                          label: l10n.editar,
                        ),
                        SlidableAction(
                          onPressed: (context) async {
                            if (a.id != null) {
                              await db.eliminarActivo(a.id!);
                              setState(() => _bolsaSincronizada = false);
                              _sincronizarBolsaAutomaticamente();
                            }
                          },
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: l10n.borrar,
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: Icon(iconosTipoInversion[a.tipoEfectivo], color: Theme.of(context).colorScheme.onSurfaceVariant),
                      title: Text(a.nombreVisible, style: const TextStyle(fontWeight: FontWeight.bold)),
                      // Con nombre propio, debajo se ve el ticker o el ISIN
                      subtitle: Text(
                        [
                          if (a.nombreVisible != a.ticker) a.isin ?? a.ticker,
                          l10n.resumenActivo('${a.cantidad.abs()}', _moneda.formatear(a.precioCompra), _moneda.formatear(precioMercado)),
                        ].join('\n'),
                      ),
                      isThreeLine: a.nombreVisible != a.ticker,
                      trailing: Text(
                        '${esCompra ? '+' : '-'}${_moneda.formatear(valorActualOperacion)}',
                        style: TextStyle(color: esCompra ? Theme.of(context).colorScheme.onSurfaceVariant : AppColors.advertencia, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
