import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:presupuesto_familiar/constants/app_colors.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_extractos.dart';
import 'package:presupuesto_familiar/utilidades/moneda.dart';

// Pide un extracto (Norma 43 o CSV) y abre la previsualización para la cuenta.
// Devuelve true si se importó algo o se actualizó el saldo.
Future<bool> importarExtracto(BuildContext context, CuentaBancaria cuenta) async {
  final l10n = AppLocalizations.of(context);
  final mensajero = ScaffoldMessenger.of(context);
  final navegador = Navigator.of(context);

  final ficheros = await FilePicker.pickFiles(type: FileType.any);
  if (ficheros.isEmpty) return false;
  final bytes = await ficheros.first.readAsBytes();

  List<ExtractoCuenta> extractos;
  try {
    extractos = ServicioExtractos.leer(bytes);
  } on FormatoExtractoNoValido {
    mensajero.showSnackBar(SnackBar(content: Text(l10n.extractoNoValido)));
    return false;
  }

  // En Norma 43 puede haber varias cuentas: se usa la que coincide con el IBAN de esta cuenta
  final extracto = await _extractoDeLaCuenta(extractos, cuenta);
  final importado = await navegador.push<bool>(MaterialPageRoute(
    builder: (context) => PantallaImportarExtracto(cuenta: cuenta, extracto: extracto),
  ));
  return importado ?? false;
}

Future<ExtractoCuenta> _extractoDeLaCuenta(List<ExtractoCuenta> extractos, CuentaBancaria cuenta) async {
  for (final e in extractos) {
    if (e.entidad == null) continue;
    final propia = await ServicioCuentasAhorro.buscarPorCcc(e.entidad!, e.oficina!, e.numeroCuenta!);
    if (propia?.id == cuenta.id) return e;
  }
  return extractos.first;
}

// Previsualización: el usuario elige qué movimientos importar (ninguno por defecto)
// y si quiere actualizar el saldo de la cuenta con el del extracto.
class PantallaImportarExtracto extends StatefulWidget {
  final CuentaBancaria cuenta;
  final ExtractoCuenta extracto;
  // Marcar de entrada todos los movimientos que aún no están en el presupuesto (sincronización con el banco)
  final bool preseleccionar;
  // Días de margen para reconocer como ya importado un gasto con el mismo importe (ver ServicioExtractos)
  final int margenDias;

  const PantallaImportarExtracto({
    super.key,
    required this.cuenta,
    required this.extracto,
    this.preseleccionar = false,
    this.margenDias = 0,
  });

  @override
  State<PantallaImportarExtracto> createState() => _PantallaImportarExtractoState();
}

class _PantallaImportarExtractoState extends State<PantallaImportarExtracto> {
  Set<int> _repetidos = {};
  List<String> _categorias = [];
  late final List<String> _categoriaDe = widget.extracto.movimientos.map(ServicioExtractos.sugerirCategoria).toList();
  final Set<int> _elegidos = {};
  late bool _actualizarSaldo = widget.extracto.saldoFinal != null;
  bool _cargando = true;
  bool _importando = false;

  List<MovimientoExtracto> get _movimientos => widget.extracto.movimientos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final existentes = await ServicioExtractos.movimientosExistentes();
    final categorias = await ServicioExtractos.categorias();
    if (!mounted) return;
    setState(() {
      _repetidos = ServicioExtractos.indicesYaImportados(_movimientos, existentes, margenDias: widget.margenDias);
      _categorias = categorias;
      _cargando = false;
      if (widget.preseleccionar) {
        for (var i = 0; i < _movimientos.length; i++) {
          if (!_yaImportado(i)) _elegidos.add(i);
        }
      }
    });
  }

  bool _yaImportado(int i) => _repetidos.contains(i);

  void _elegirGastos() => setState(() {
        for (var i = 0; i < _movimientos.length; i++) {
          if (!_movimientos[i].esIngreso && !_yaImportado(i)) _elegidos.add(i);
        }
      });

  Future<void> _importar() async {
    setState(() => _importando = true);
    final saldo = widget.extracto.saldoFinal;
    if (_actualizarSaldo && saldo != null) {
      await ServicioCuentasAhorro.actualizarSaldo(widget.cuenta.id, saldo, fecha: widget.extracto.fechaSaldo);
    }
    final indices = _elegidos.toList()..sort();
    await ServicioExtractos.importar([for (final i in indices) (_movimientos[i], _categoriaDe[i])]);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.extractoImportado(indices.length))));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final moneda = Moneda.of(context);
    final saldo = widget.extracto.saldoFinal;
    final puedeConfirmar = !_importando && (_elegidos.isNotEmpty || (_actualizarSaldo && saldo != null));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.importarExtracto)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: AppNumbers.tamanoBotonFlotante + AppNumbers.paddingLargo),
              children: [
                if (saldo != null)
                  SwitchListTile(
                    secondary: Icon(Icons.account_balance_wallet, color: Theme.of(context).colorScheme.primary),
                    title: Text(l10n.actualizarSaldoA(moneda.formatear(saldo))),
                    subtitle: Text(widget.cuenta.nombreCompleto),
                    value: _actualizarSaldo,
                    onChanged: (v) => setState(() => _actualizarSaldo = v),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingStandard),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l10n.movimientosExtracto(_movimientos.length),
                            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                      ),
                      TextButton(onPressed: _elegirGastos, child: Text(l10n.elegirGastos)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppNumbers.paddingStandard),
                  child: Text(l10n.importarExtractoAyuda, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                for (var i = 0; i < _movimientos.length; i++) _fila(i, l10n, moneda),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: puedeConfirmar ? _importar : null,
        // El FAB no tiene estado desactivado propio: se usan los colores de Material 3 para desactivado
        backgroundColor: puedeConfirmar ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
        foregroundColor: puedeConfirmar ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
        elevation: puedeConfirmar ? null : 0,
        icon: const Icon(Icons.download_done),
        label: Text(_elegidos.isEmpty ? l10n.soloSaldo : l10n.importarN(_elegidos.length)),
      ),
    );
  }

  Widget _fila(int i, AppLocalizations l10n, Moneda moneda) {
    final m = _movimientos[i];
    final repetido = _yaImportado(i);
    final fecha = '${m.fecha.day.toString().padLeft(2, '0')}/${m.fecha.month.toString().padLeft(2, '0')}/${m.fecha.year}';
    return CheckboxListTile(
      value: _elegidos.contains(i),
      onChanged: repetido ? null : (v) => setState(() => v == true ? _elegidos.add(i) : _elegidos.remove(i)),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(m.concepto.isEmpty ? '—' : m.concepto, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Text(repetido ? '$fecha · ${l10n.yaImportado}' : fecha),
          const SizedBox(width: AppNumbers.paddingCorto),
          if (!repetido)
            PopupMenuButton<String>(
              tooltip: l10n.categoria,
              onSelected: (c) => setState(() => _categoriaDe[i] = c),
              itemBuilder: (context) => _categorias.map((c) => PopupMenuItem(value: c, child: Text(l10n.nombreCategoria(c)))).toList(),
              child: Chip(
                label: Text(l10n.nombreCategoria(_categoriaDe[i]), style: const TextStyle(fontSize: AppNumbers.fontSizePequeno)),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      secondary: Text(
        moneda.formatear(m.importe, conSigno: true),
        style: TextStyle(fontWeight: FontWeight.bold, color: m.esIngreso ? AppColors.exito : AppColors.error),
      ),
    );
  }
}
