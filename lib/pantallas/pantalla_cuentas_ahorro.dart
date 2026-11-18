import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/campo_banco.dart';
import 'package:presupuesto_familiar/pantallas/conectar_banco.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_importar_extracto.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/utilidades/dialogo_texto.dart';
import 'package:presupuesto_familiar/utilidades/iban.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

// Crea (o edita) una cuenta bancaria. Devuelve la cuenta guardada o null si se cancela.
// Por defecto crea cuentas de ahorro (se abre desde la sección Ahorro).
Future<CuentaBancaria?> mostrarDialogoCuentaAhorro(
  BuildContext context, {
  CuentaBancaria? editar,
  TipoCuenta tipo = TipoCuenta.ahorro,
}) {
  return showDialog<CuentaBancaria>(
    context: context,
    builder: (context) => _DialogoCuentaAhorro(editar: editar, tipoInicial: tipo),
  );
}

// Escribe el IBAN en mayúsculas y en grupos de 4
class _FormatoIban extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue antes, TextEditingValue despues) {
    final texto = Iban.formatear(Iban.normalizar(despues.text));
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
  }
}

class _DialogoCuentaAhorro extends StatefulWidget {
  final CuentaBancaria? editar;
  final TipoCuenta tipoInicial;
  const _DialogoCuentaAhorro({this.editar, required this.tipoInicial});

  @override
  State<_DialogoCuentaAhorro> createState() => _DialogoCuentaAhorroState();
}

class _DialogoCuentaAhorroState extends State<_DialogoCuentaAhorro> {
  // Los controladores viven en el State: se liberan cuando el diálogo ya ha desaparecido
  late final TextEditingController _nombre = TextEditingController(text: widget.editar?.nombre ?? '');
  late final TextEditingController _banco = TextEditingController(text: widget.editar?.banco ?? '');
  late final TextEditingController _iban = TextEditingController(text: Iban.formatear(widget.editar?.iban ?? ''));
  final TextEditingController _saldo = TextEditingController();
  late TipoCuenta _tipo = widget.editar?.tipo ?? widget.tipoInicial;
  late String? _bancoId = widget.editar?.bancoId;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _banco.dispose();
    _iban.dispose();
    _saldo.dispose();
    super.dispose();
  }

  String get _ibanNormalizado => Iban.normalizar(_iban.text);

  // Solo se marca como erróneo cuando ya tiene la longitud de su país
  bool get _ibanIncorrecto {
    final iban = _ibanNormalizado;
    if (iban.isEmpty) return false;
    final longitud = Iban.longitudes[Iban.pais(iban)] ?? 15;
    return iban.length >= longitud && !Iban.esValido(iban);
  }

  void _alCambiarIban(String _) {
    final detectado = CatalogoBancos.detectar(_ibanNormalizado);
    if (detectado != null && detectado.id != _bancoId) _elegirBanco(detectado);
    setState(() {});
  }

  void _elegirBanco(BancoCatalogo banco) {
    final l10n = AppLocalizations.of(context);
    _bancoId = banco.id;
    _banco.text = banco.nombre;
    if (_nombre.text.trim().isEmpty) _nombre.text = l10n.cuentaDe(banco.nombre);
    setState(() {});
  }

  // Si el texto coincide con un banco del catálogo, se enlaza aunque no se haya elegido de la lista
  String? _bancoIdFinal() {
    final elegido = CatalogoBancos.porId(_bancoId);
    if (elegido != null && elegido.nombre.toLowerCase() == _banco.text.trim().toLowerCase()) return elegido.id;
    return bancoPorTexto(_banco.text)?.id;
  }

  Future<void> _pegarIban() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = datos?.text;
    if (texto == null || !mounted) return;
    _iban.text = Iban.formatear(Iban.normalizar(texto));
    _alCambiarIban(_iban.text);
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty || _ibanIncorrecto || _guardando) return;
    if (_ibanNormalizado.isNotEmpty && !Iban.esValido(_ibanNormalizado)) return;
    setState(() => _guardando = true);
    final editar = widget.editar;
    final bancoId = _bancoIdFinal();
    final saldo = double.tryParse(_saldo.text.replaceAll(',', '.').trim());
    CuentaBancaria guardada;
    if (editar == null) {
      guardada = await ServicioCuentasAhorro.anadir(
        _nombre.text,
        _banco.text,
        tipo: _tipo,
        iban: _ibanNormalizado,
        bancoId: bancoId,
        saldo: saldo,
      );
    } else {
      await ServicioCuentasAhorro.editar(editar.id,
          nombre: _nombre.text, banco: _banco.text, iban: _ibanNormalizado, bancoId: bancoId ?? '');
      guardada = editar.copiar(
        nombre: _nombre.text.trim(),
        banco: _banco.text.trim(),
        iban: _ibanNormalizado,
        quitarIban: _ibanNormalizado.isEmpty,
        bancoId: bancoId,
        quitarBancoId: bancoId == null,
      );
    }
    if (mounted) Navigator.pop(context, guardada);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final esNueva = widget.editar == null;
    final banco = CatalogoBancos.porId(_bancoIdFinal() ?? _bancoId);

    return AlertDialog(
      title: Text(esNueva ? (_tipo == TipoCuenta.ahorro ? l10n.nuevaCuentaAhorro : l10n.nuevaCuenta) : l10n.editarCuentaAhorro),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (esNueva) ...[
              SegmentedButton<TipoCuenta>(
                segments: [
                  ButtonSegment(value: TipoCuenta.corriente, label: Text(l10n.corriente)),
                  ButtonSegment(value: TipoCuenta.ahorro, label: Text(l10n.ahorro)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
              const SizedBox(height: AppNumbers.paddingMedio),
            ],
            // El IBAN va primero: al escribirlo o pegarlo se reconoce el banco
            TextField(
              controller: _iban,
              autofocus: esNueva,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_FormatoIban()],
              onChanged: _alCambiarIban,
              decoration: InputDecoration(
                labelText: l10n.ibanOpcional,
                prefixIcon: const Icon(Icons.numbers),
                errorText: _ibanIncorrecto ? l10n.ibanNoValido : null,
                suffixIcon: IconButton(tooltip: l10n.pegar, icon: const Icon(Icons.content_paste), onPressed: _pegarIban),
              ),
            ),
            const SizedBox(height: AppNumbers.paddingMedio),
            CampoBanco(
              controlador: _banco,
              banco: banco,
              alElegir: _elegirBanco,
              alEscribir: () => setState(() => _bancoId = null),
            ),
            const SizedBox(height: AppNumbers.paddingMedio),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.nombreDeCuenta, prefixIcon: const Icon(Icons.savings)),
            ),
            if (esNueva) ...[
              const SizedBox(height: AppNumbers.paddingMedio),
              TextField(
                controller: _saldo,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onSubmitted: (_) => _guardar(),
                decoration: InputDecoration(
                  labelText: l10n.saldoOpcional,
                  prefixIcon: const Icon(Icons.account_balance_wallet),
                  suffixText: Moneda.of(context).simbolo,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelar)),
        ElevatedButton(onPressed: _guardando ? null : _guardar, child: Text(l10n.guardar)),
      ],
    );
  }
}

// Ahorro > Gestionar cuentas (solo ahorro) y Configuración > Cuentas bancarias (todas)
class PantallaCuentasAhorro extends StatefulWidget {
  final bool todas;
  const PantallaCuentasAhorro({super.key, this.todas = false});

  @override
  State<PantallaCuentasAhorro> createState() => _PantallaCuentasAhorroState();
}

class _PantallaCuentasAhorroState extends State<PantallaCuentasAhorro> {
  List<CuentaBancaria> _cuentas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final cuentas = widget.todas ? await ServicioCuentasAhorro.cargarTodas() : await ServicioCuentasAhorro.cargar();
    if (mounted) setState(() => _cuentas = cuentas);
  }

  Future<void> _anadir() async {
    final tipo = widget.todas ? TipoCuenta.corriente : TipoCuenta.ahorro;
    final nueva = await mostrarDialogoCuentaAhorro(context, tipo: tipo);
    if (nueva == null || !mounted) return;
    _cargar();
    // Atajo: añadir la tarjeta de la cuenta con el banco ya elegido
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.cuentaGuardada),
      action: SnackBarAction(
        label: l10n.anadirSuTarjeta,
        onPressed: () => mostrarDialogoNuevaTarjeta(context, bancoId: nueva.bancoId),
      ),
    ));
  }

  Future<void> _editar(CuentaBancaria cuenta) async {
    if (await mostrarDialogoCuentaAhorro(context, editar: cuenta) != null) _cargar();
  }

  Future<void> _marcarPrincipal(CuentaBancaria cuenta) async {
    await ServicioCuentasAhorro.marcarPrincipal(cuenta.id);
    _cargar();
  }

  Future<void> _actualizarSaldo(CuentaBancaria cuenta) async {
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);
    final texto = await mostrarDialogoTexto(
      context,
      titulo: l10n.actualizarSaldo,
      etiqueta: l10n.saldoActual,
      textoConfirmar: l10n.guardar,
      valorInicial: cuenta.saldo?.toStringAsFixed(moneda.decimales) ?? '',
      sufijo: moneda.simbolo,
      icono: Icons.account_balance_wallet,
      teclado: const TextInputType.numberWithOptions(decimal: true, signed: true),
      validar: (t) async => double.tryParse(t.replaceAll(',', '.').trim()) != null,
    );
    if (texto == null) return;
    await ServicioCuentasAhorro.actualizarSaldo(cuenta.id, double.parse(texto.replaceAll(',', '.').trim()));
    _cargar();
  }

  Future<void> _importar(CuentaBancaria cuenta) async {
    if (await importarExtracto(context, cuenta)) _cargar();
  }

  Future<void> _conectar(CuentaBancaria cuenta) async {
    await conectarCuentaConBanco(context, cuenta);
    _cargar();
  }

  Future<void> _sincronizar(CuentaBancaria cuenta) async {
    await sincronizarCuenta(context, cuenta);
    _cargar();
  }

  Future<void> _desconectar(CuentaBancaria cuenta) async {
    if (await desconectarCuentaDelBanco(context, cuenta)) _cargar();
  }

  Future<void> _verHistorial(CuentaBancaria cuenta) async {
    final apuntes = (await ServicioCuentasAhorro.historial(cuenta.id)).reversed.toList();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.historialSaldo, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(cuenta.nombreCompleto)),
            for (var i = 0; i < apuntes.length; i++)
              ListTile(
                dense: true,
                title: Text(_fecha(apuntes[i].fecha)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Variación respecto al apunte anterior
                    if (i + 1 < apuntes.length)
                      Text(
                        moneda.formatear(apuntes[i].saldo - apuntes[i + 1].saldo, conSigno: true),
                        style: TextStyle(
                          fontSize: AppNumbers.fontSizePequeno,
                          color: apuntes[i].saldo >= apuntes[i + 1].saldo ? AppColors.exito : AppColors.error,
                        ),
                      ),
                    const SizedBox(width: AppNumbers.paddingMedio),
                    Text(moneda.formatear(apuntes[i].saldo), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _fecha(DateTime f) => '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  Future<void> _eliminar(CuentaBancaria cuenta) async {
    final l10n = AppLocalizations.of(context);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.eliminarCuentaConfirmar(cuenta.nombreCompleto)),
        content: cuenta.esAhorro ? Text(l10n.eliminarCuentaAviso) : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelar)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.borrar),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await ServicioCuentasAhorro.eliminar(cuenta.id);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final corrientes = _cuentas.where((c) => !c.esAhorro).toList();
    final ahorro = _cuentas.where((c) => c.esAhorro).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.todas ? l10n.cuentasBancarias : l10n.cuentasAhorro)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppNumbers.tamanoBotonFlotante + AppNumbers.paddingLargo),
        children: [
          if (widget.todas) ...[
            _cabecera(l10n.cuentasCorrientes),
            if (corrientes.isEmpty) _nota(l10n.sinCuentasCorrientes),
            ...corrientes.map((c) => _fila(c, l10n)),
            _cabecera(l10n.cuentasAhorro),
          ],
          _nota(ahorro.isEmpty ? l10n.sinCuentasAhorro : l10n.cuentaPrincipalExplicacion),
          ...ahorro.map((c) => _fila(c, l10n)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _anadir,
        icon: const Icon(Icons.add),
        label: Text(l10n.anadirCuenta),
      ),
    );
  }

  Widget _cabecera(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(AppNumbers.paddingStandard, AppNumbers.paddingStandard, AppNumbers.paddingStandard, 0),
        child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _nota(String texto) => Padding(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        child: Text(texto, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _fila(CuentaBancaria cuenta, AppLocalizations l10n) {
    final moneda = Moneda.of(context);
    final saldo = cuenta.saldo;
    final fecha = cuenta.saldoFecha;
    return ListTile(
      leading: AvatarBanco(banco: cuenta.bancoCatalogo),
      title: Row(
        children: [
          Flexible(child: Text(cuenta.nombre, overflow: TextOverflow.ellipsis)),
          if (cuenta.principal) ...[
            const SizedBox(width: 4),
            Icon(Icons.star, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ],
      ),
      subtitle: Text([
        if (cuenta.banco.isNotEmpty) cuenta.banco,
        if (cuenta.iban != null) Iban.enmascarar(cuenta.iban!),
        if (cuenta.principal) l10n.cuentaPrincipal,
        if (cuenta.enlace != null) cuenta.enlace!.caducado() ? l10n.conexionCaducada : l10n.conectadaConBanco,
      ].join(' · ')),
      onTap: () => _editar(cuenta),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saldo != null)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(moneda.formatear(saldo), style: const TextStyle(fontWeight: FontWeight.bold)),
                if (fecha != null)
                  Text('${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: AppNumbers.fontSizePequeno, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          PopupMenuButton<String>(
            onSelected: (accion) {
              if (accion == 'saldo') _actualizarSaldo(cuenta);
              if (accion == 'importar') _importar(cuenta);
              if (accion == 'conectar') _conectar(cuenta);
              if (accion == 'sincronizar') _sincronizar(cuenta);
              if (accion == 'desconectar') _desconectar(cuenta);
              if (accion == 'historial') _verHistorial(cuenta);
              if (accion == 'principal') _marcarPrincipal(cuenta);
              if (accion == 'borrar') _eliminar(cuenta);
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'saldo', child: Text(l10n.actualizarSaldo)),
              // Con la cuenta conectada al banco, sincronizar sustituye a escribir el saldo o importar a mano
              if (cuenta.conectada && !cuenta.enlace!.caducado())
                PopupMenuItem(value: 'sincronizar', child: Text(l10n.sincronizarBanco))
              else
                PopupMenuItem(value: 'conectar', child: Text(l10n.conectarConBanco)),
              PopupMenuItem(value: 'importar', child: Text(l10n.importarExtracto)),
              if (cuenta.conectada) PopupMenuItem(value: 'desconectar', child: Text(l10n.desconectarBanco)),
              if (saldo != null) PopupMenuItem(value: 'historial', child: Text(l10n.historialSaldo)),
              if (cuenta.esAhorro && !cuenta.principal) PopupMenuItem(value: 'principal', child: Text(l10n.hacerPrincipal)),
              PopupMenuItem(value: 'borrar', child: Text(l10n.borrar)),
            ],
          ),
        ],
      ),
    );
  }
}
