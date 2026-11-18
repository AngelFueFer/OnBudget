import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/campo_banco.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/detector_pagos.dart';
import 'package:presupuesto_familiar/servicios/servicio_notificaciones.dart';
import 'package:presupuesto_familiar/servicios/servicio_pagos_detectados.dart';
import 'package:presupuesto_familiar/servicios/servicio_tarjetas.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

// Alta rápida de una tarjeta: banco, red, tipo y últimos 4 dígitos (nunca el número completo).
// Devuelve el nombre de la tarjeta guardada o null si se cancela.
Future<String?> mostrarDialogoNuevaTarjeta(BuildContext context, {String? bancoId}) {
  return showDialog<String>(context: context, builder: (context) => _DialogoNuevaTarjeta(bancoId: bancoId));
}

class _DialogoNuevaTarjeta extends StatefulWidget {
  final String? bancoId;
  const _DialogoNuevaTarjeta({this.bancoId});

  @override
  State<_DialogoNuevaTarjeta> createState() => _DialogoNuevaTarjetaState();
}

class _DialogoNuevaTarjetaState extends State<_DialogoNuevaTarjeta> {
  static const List<String> _redes = ['Visa', 'Mastercard', 'Amex', 'Maestro'];

  // Los controladores viven en el State: se liberan cuando el diálogo ya ha desaparecido
  late final TextEditingController _banco = TextEditingController(text: CatalogoBancos.porId(widget.bancoId)?.nombre ?? '');
  final TextEditingController _digitos = TextEditingController();
  List<CuentaBancaria> _cuentas = [];
  String? _red = _redes.first;
  TipoTarjeta _tipo = TipoTarjeta.debito;
  bool _repetida = false;

  @override
  void initState() {
    super.initState();
    ServicioCuentasAhorro.cargarTodas().then((cuentas) {
      if (mounted) setState(() => _cuentas = cuentas);
    });
  }

  @override
  void dispose() {
    _banco.dispose();
    _digitos.dispose();
    super.dispose();
  }

  // Bancos de las cuentas del usuario, para elegirlos con un toque
  List<String> get _bancosDelUsuario {
    final vistos = <String>{};
    return [
      for (final c in _cuentas)
        if (c.banco.isNotEmpty && vistos.add(c.banco.toLowerCase())) c.banco,
    ];
  }

  bool get _digitosValidos => _digitos.text.isEmpty || RegExp(r'^\d{4}$').hasMatch(_digitos.text);

  // 'Visa BBVA ••1234', 'Mastercard ING crédito ••9876'
  String _nombre(AppLocalizations l10n) => [
        ?_red,
        if (_banco.text.trim().isNotEmpty) _banco.text.trim(),
        if (_tipo == TipoTarjeta.credito) l10n.credito.toLowerCase(),
        if (_digitos.text.length == 4) '••${_digitos.text}',
      ].join(' ');

  // Una tarjeta de débito de un banco con una sola cuenta corriente queda asociada a ella (solo informativo)
  String? _cuentaAsociada() {
    if (_tipo != TipoTarjeta.debito) return null;
    final banco = _banco.text.trim().toLowerCase();
    final candidatas = _cuentas.where((c) => !c.esAhorro && c.banco.toLowerCase() == banco).toList();
    return candidatas.length == 1 ? candidatas.single.id : null;
  }

  void _cambiar(VoidCallback cambio) => setState(() {
        cambio();
        _repetida = false;
      });

  Future<void> _guardar() async {
    final nombre = _nombre(AppLocalizations.of(context));
    if (nombre.isEmpty || !_digitosValidos) return;
    final tarjeta = Tarjeta(
      nombre: nombre,
      red: _red,
      tipo: _tipo,
      ultimos4: _digitos.text.length == 4 ? _digitos.text : null,
      bancoId: bancoPorTexto(_banco.text)?.id,
      cuentaId: _cuentaAsociada(),
    );
    if (!await ServicioTarjetas.anadirTarjeta(tarjeta)) {
      if (mounted) setState(() => _repetida = true);
      return;
    }
    if (mounted) Navigator.pop(context, nombre);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nombre = _nombre(l10n);
    final puedeGuardar = nombre.isNotEmpty && _digitosValidos;

    return AlertDialog(
      title: Text(l10n.nuevaTarjeta),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_bancosDelUsuario.isNotEmpty) ...[
              Wrap(
                spacing: AppNumbers.paddingCorto,
                children: _bancosDelUsuario
                    .map((b) => ChoiceChip(
                          avatar: AvatarBanco(banco: bancoPorTexto(b), radio: 10),
                          label: Text(b),
                          selected: _banco.text.trim().toLowerCase() == b.toLowerCase(),
                          onSelected: (_) => _cambiar(() => _banco.text = b),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppNumbers.paddingCorto),
            ],
            CampoBanco(
              controlador: _banco,
              alElegir: (b) => _cambiar(() => _banco.text = b.nombre),
              alEscribir: () => _cambiar(() {}),
            ),
            const SizedBox(height: AppNumbers.paddingMedio),
            Wrap(
              spacing: AppNumbers.paddingCorto,
              children: _redes
                  .map((r) => ChoiceChip(
                        label: Text(r),
                        selected: _red == r,
                        onSelected: (elegida) => _cambiar(() => _red = elegida ? r : null),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppNumbers.paddingCorto),
            SegmentedButton<TipoTarjeta>(
              segments: [
                ButtonSegment(value: TipoTarjeta.debito, label: Text(l10n.debito)),
                ButtonSegment(value: TipoTarjeta.credito, label: Text(l10n.credito)),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => _cambiar(() => _tipo = s.first),
            ),
            const SizedBox(height: AppNumbers.paddingMedio),
            TextField(
              controller: _digitos,
              autofocus: widget.bancoId != null,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _cambiar(() {}),
              onSubmitted: (_) => _guardar(),
              decoration: InputDecoration(
                labelText: l10n.ultimos4Digitos,
                prefixText: '•••• ',
                helperText: l10n.nombreTarjetaAyuda,
                helperMaxLines: 2,
                errorText: _repetida ? l10n.tarjetaRepetida : null,
              ),
            ),
            if (nombre.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.credit_card, color: Theme.of(context).colorScheme.primary),
                title: Text(nombre),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelar)),
        ElevatedButton(onPressed: puedeGuardar ? _guardar : null, child: Text(l10n.anadir)),
      ],
    );
  }
}

// Configuración > Mis tarjetas
class PantallaTarjetas extends StatelessWidget {
  const PantallaTarjetas({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).misTarjetas)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(AppNumbers.paddingStandard),
        child: PanelTarjetas(),
      ),
    );
  }
}

// Importación desde wallets (lectura de notificaciones) + tarjetas guardadas.
// Se usa en el onboarding y en Configuración.
class PanelTarjetas extends StatefulWidget {
  const PanelTarjetas({super.key});

  @override
  State<PanelTarjetas> createState() => _PanelTarjetasState();
}

class _PanelTarjetasState extends State<PanelTarjetas> with WidgetsBindingObserver {
  List<Tarjeta> _tarjetas = [];
  bool _tienePermiso = false;
  bool _activado = false;
  bool _bateriaSinRestricciones = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de los ajustes de Android, comprueba si se concedió el permiso
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    final tarjetas = await ServicioTarjetas.cargarTarjetas();
    final permiso = await ServicioNotificaciones.tienePermiso();
    final activado = await ServicioNotificaciones.estaActivado();
    final bateria = await ServicioNotificaciones.bateriaSinRestricciones();
    if (!mounted) return;
    setState(() {
      _tarjetas = tarjetas;
      _tienePermiso = permiso;
      _activado = activado && permiso;
      _bateriaSinRestricciones = bateria;
    });
  }

  Future<void> _pedirPermiso() async {
    if (await ServicioNotificaciones.pedirPermiso()) {
      await ServicioNotificaciones.activar(true);
      await ServicioNotificaciones.pedirBateriaSinRestricciones();
    }
    await _cargar();
  }

  // Al activar se pide también quitar la restricción de batería, para que lea con la app cerrada
  Future<void> _cambiarActivado(bool valor) async {
    await ServicioNotificaciones.activar(valor);
    if (valor) await ServicioNotificaciones.pedirBateriaSinRestricciones();
    await _cargar();
  }

  Future<void> _anadirManual() async {
    if (await mostrarDialogoNuevaTarjeta(context) != null) _cargar();
  }

  Future<void> _eliminar(Tarjeta tarjeta) async {
    setState(() => _tarjetas.remove(tarjeta));
    await ServicioTarjetas.eliminar(tarjeta.nombre);
  }

  Future<void> _aceptarDetectada(String tarjeta) async {
    await ServicioNotificaciones.aceptar(tarjeta);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _construirImportacion(l10n),
        const SizedBox(height: AppNumbers.paddingLargo),
        Text(l10n.misTarjetas, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        if (_tarjetas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppNumbers.paddingMedio),
            child: Text(l10n.ningunaTarjeta, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ..._tarjetas.map((tarjeta) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: tarjeta.banco != null
                  ? AvatarBanco(banco: tarjeta.banco)
                  : Icon(Icons.credit_card, color: Theme.of(context).colorScheme.primary),
              title: Text(tarjeta.nombre),
              subtitle: tarjeta.tipo == null ? null : Text(tarjeta.tipo == TipoTarjeta.credito ? l10n.credito : l10n.debito),
              trailing: IconButton(
                icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.onSurfaceVariant),
                tooltip: AppLocalizations.of(context).borrar,
                onPressed: () => _eliminar(tarjeta),
              ),
            )),
        const SizedBox(height: AppNumbers.paddingCorto),
        OutlinedButton.icon(
          onPressed: _anadirManual,
          icon: const Icon(Icons.add),
          label: Text(l10n.anadirTarjeta),
        ),
      ],
    );
  }

  Widget _construirImportacion(AppLocalizations l10n) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: AppNumbers.opacityLigera),
      child: Padding(
        padding: const EdgeInsets.all(AppNumbers.paddingStandard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppNumbers.paddingCorto),
                Expanded(child: Text(l10n.importarTarjetas, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: AppNumbers.paddingCorto),
            Text(l10n.importarTarjetasDescripcion, style: TextStyle(fontSize: AppNumbers.fontSizeAyuda, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppNumbers.paddingMedio),
            if (!ServicioNotificaciones.soportado)
              Text(l10n.soloAndroid, style: const TextStyle(fontStyle: FontStyle.italic))
            else if (!_tienePermiso)
              ElevatedButton.icon(
                onPressed: _pedirPermiso,
                icon: const Icon(Icons.notifications_active),
                label: Text(l10n.permitirNotificaciones),
              )
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.lecturaNotificaciones),
                subtitle: Text(l10n.permisoConcedido),
                value: _activado,
                onChanged: _cambiarActivado,
              ),
              if (_activado && !_bateriaSinRestricciones) _construirAvisoBateria(l10n),
              _construirDetectadas(l10n),
              _construirPagosDetectados(l10n),
            ],
          ],
        ),
      ),
    );
  }

  // Con la batería restringida, Android puede cortar la lectura cuando la app está cerrada
  Widget _construirAvisoBateria(AppLocalizations l10n) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.battery_alert, color: Colors.orange),
      title: Text(l10n.bateriaRestringida),
      subtitle: Text(l10n.bateriaRestringidaDescripcion),
      trailing: TextButton(
        onPressed: ServicioNotificaciones.pedirBateriaSinRestricciones,
        child: Text(l10n.quitarRestriccion),
      ),
    );
  }

  Widget _construirDetectadas(AppLocalizations l10n) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: ServicioNotificaciones.detectadas,
      builder: (context, detectadas, _) {
        if (!_activado) return const SizedBox();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tarjetasDetectadas, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (detectadas.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppNumbers.paddingCorto),
                child: Text(l10n.sinTarjetasDetectadas, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ...detectadas.map((tarjeta) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.credit_card),
                  title: Text(tarjeta),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.descartar,
                        icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => ServicioNotificaciones.descartar(tarjeta),
                      ),
                      IconButton(
                        tooltip: l10n.anadir,
                        icon: const Icon(Icons.check_circle, color: AppColors.exito),
                        onPressed: () => _aceptarDetectada(tarjeta),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }

  // Pagos leídos de notificaciones bancarias: se añaden como gasto o se descartan
  Widget _construirPagosDetectados(AppLocalizations l10n) {
    return ValueListenableBuilder<List<PagoDetectado>>(
      valueListenable: ServicioPagosDetectados.pendientes,
      builder: (context, pagos, _) {
        if (!_activado || pagos.isEmpty) return const SizedBox();
        final moneda = Moneda.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppNumbers.paddingMedio),
            Text(l10n.pagosDetectados, style: const TextStyle(fontWeight: FontWeight.bold)),
            ...pagos.map((pago) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AvatarBanco(banco: CatalogoBancos.porId(pago.bancoId), radio: 14),
                  title: Text('${pago.comercio} · ${moneda.formatear(pago.importe)}'),
                  subtitle: Text([
                    '${pago.fecha.day.toString().padLeft(2, '0')}/${pago.fecha.month.toString().padLeft(2, '0')}',
                    if (pago.ultimos4 != null) '••${pago.ultimos4}',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.descartar,
                        icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => ServicioPagosDetectados.descartar(pago),
                      ),
                      IconButton(
                        tooltip: l10n.anadirGasto,
                        icon: const Icon(Icons.check_circle, color: AppColors.exito),
                        onPressed: () => ServicioPagosDetectados.confirmar(pago),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }
}
