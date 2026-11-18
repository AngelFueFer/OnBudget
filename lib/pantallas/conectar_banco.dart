import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:presupuesto_familiar/constants/app_numbers.dart';
import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/pantallas/campo_banco.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_conexion_bancos.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_importar_extracto.dart';
import 'package:presupuesto_familiar/servicios/open_banking/config_open_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';
import 'package:presupuesto_familiar/servicios/open_banking/servicio_sincronizacion_bancaria.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/utilidades/dialogo_texto.dart';
import 'package:presupuesto_familiar/utilidades/iban.dart';

// Conecta una cuenta de la app con su banco por Open Banking:
// elegir banco -> autorizar en la web del banco -> pegar la dirección de vuelta -> elegir la cuenta.
// Al terminar descarga saldo y movimientos. Devuelve true si la cuenta quedó conectada.
Future<bool> conectarCuentaConBanco(BuildContext context, CuentaBancaria cuenta) async {
  final l10n = AppLocalizations.of(context);
  final mensajero = ScaffoldMessenger.of(context);

  if (!ConfigOpenBanking.configurada) {
    mensajero.showSnackBar(SnackBar(
      content: Text(l10n.configuraConexionBancos),
      action: SnackBarAction(
        label: l10n.configurar,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaConexionBancos())),
      ),
    ));
    return false;
  }

  final api = ServicioSincronizacionBancaria.proveedor();
  try {
    final bancos = await _conEspera(context, () => api.bancos(ConfigOpenBanking.pais));
    if (bancos == null || !context.mounted) return false;
    final banco = await showDialog<BancoDisponible>(
      context: context,
      builder: (_) => _DialogoElegirBanco(bancos: ServicioSincronizacionBancaria.ordenarPara(bancos, cuenta)),
    );
    if (banco == null || !context.mounted) return false;

    final estado = ServicioSincronizacionBancaria.nuevoEstado();
    final url = await _conEspera(
      context,
      () => api.iniciarAutorizacion(
        banco: banco,
        urlVuelta: ConfigOpenBanking.urlVuelta,
        estado: estado,
        validaHasta: ServicioSincronizacionBancaria.validezConsentimiento(banco),
      ),
    );
    if (url == null || !context.mounted) return false;
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      throw const ErrorBancario('No se pudo abrir el navegador');
    }
    if (!context.mounted) return false;

    final pegado = await mostrarDialogoTexto(
      context,
      titulo: l10n.autorizaEnBanco,
      etiqueta: l10n.direccionVuelta,
      textoConfirmar: l10n.continuar,
      nota: l10n.autorizaEnBancoAyuda(banco.nombre),
      icono: Icons.link,
      teclado: TextInputType.url,
      validar: (t) async {
        final valido = codigoDeUrlVuelta(t, estadoEsperado: estado) != null;
        if (!valido) mensajero.showSnackBar(SnackBar(content: Text(l10n.autorizacionNoValida)));
        return valido;
      },
    );
    if (pegado == null || !context.mounted) return false;
    final codigo = codigoDeUrlVuelta(pegado, estadoEsperado: estado)!;

    final sesion = await _conEspera(context, () => api.completarAutorizacion(codigo));
    if (sesion == null || !context.mounted) return false;
    final remota = ServicioSincronizacionBancaria.cuentaCorrespondiente(sesion, cuenta) ??
        await showDialog<CuentaRemota>(context: context, builder: (_) => _DialogoElegirCuenta(sesion: sesion, cuenta: cuenta));
    if (remota == null || !context.mounted) return false;

    await ServicioSincronizacionBancaria.enlazar(cuenta, sesion, remota);
    mensajero.showSnackBar(SnackBar(content: Text(l10n.cuentaConectada(banco.nombre))));
    final conectada = (await ServicioCuentasAhorro.cargarTodas()).where((c) => c.id == cuenta.id).firstOrNull;
    if (conectada != null && context.mounted) await sincronizarCuenta(context, conectada);
    return true;
  } on ErrorBancario catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text(l10n.errorBanco(e.motivo))));
    return false;
  } catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text(l10n.errorBanco('$e'))));
    return false;
  }
}

// Descarga saldo y movimientos y abre la previsualización de importación.
// En las cuentas corrientes los movimientos nuevos vienen ya marcados; en las de ahorro, ninguno
// (sus entradas suelen ser traspasos que ya están en el presupuesto).
Future<bool> sincronizarCuenta(BuildContext context, CuentaBancaria cuenta) async {
  final l10n = AppLocalizations.of(context);
  final mensajero = ScaffoldMessenger.of(context);
  final navegador = Navigator.of(context);
  if (cuenta.enlace?.caducado() ?? false) {
    mensajero.showSnackBar(SnackBar(content: Text(l10n.reconectarBanco)));
    return false;
  }
  try {
    final extracto = await _conEspera(context, () => ServicioSincronizacionBancaria.descargar(cuenta));
    if (extracto == null) return false;
    final cuando = DateTime.now();
    // Si todo lo descargado ya está en el presupuesto no hace falta la pantalla de importación
    if (await ServicioSincronizacionBancaria.nadaNuevo(extracto)) {
      if (extracto.saldoFinal != null) {
        await ServicioCuentasAhorro.actualizarSaldo(cuenta.id, extracto.saldoFinal!, fecha: extracto.fechaSaldo);
      }
      await ServicioSincronizacionBancaria.marcarSincronizada(cuenta, cuando: cuando);
      mensajero.showSnackBar(SnackBar(content: Text(l10n.sinMovimientosNuevos)));
      return true;
    }
    final importado = await navegador.push<bool>(MaterialPageRoute(
      builder: (_) => PantallaImportarExtracto(
        cuenta: cuenta,
        extracto: extracto,
        preseleccionar: !cuenta.esAhorro,
        margenDias: ServicioSincronizacionBancaria.diasMargenDuplicados,
      ),
    ));
    if (importado == true) await ServicioSincronizacionBancaria.marcarSincronizada(cuenta, cuando: cuando);
    return importado ?? false;
  } on ErrorBancario catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text(mensajeErrorBancario(l10n, e))));
    return false;
  } catch (e) {
    // Cualquier fallo inesperado se muestra en vez de dejar la pantalla sin respuesta
    mensajero.showSnackBar(SnackBar(content: Text(l10n.errorBanco('$e'))));
    return false;
  }
}

// Texto para el usuario según el tipo de error
String mensajeErrorBancario(AppLocalizations l10n, ErrorBancario e) {
  if (e.limiteConsultas) return l10n.limiteConsultasBanco;
  if (e.requiereReconectar) return l10n.reconectarBanco;
  return l10n.errorBanco(e.motivo);
}

Future<bool> desconectarCuentaDelBanco(BuildContext context, CuentaBancaria cuenta) async {
  final l10n = AppLocalizations.of(context);
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.desconectarBancoConfirmar(cuenta.nombreCompleto)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelar)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.desconectar)),
      ],
    ),
  );
  if (confirmar != true) return false;
  await ServicioSincronizacionBancaria.desconectar(cuenta);
  return true;
}

// Muestra un diálogo de espera mientras dura la llamada. Los errores se propagan.
Future<T?> _conEspera<T>(BuildContext context, Future<T> Function() tarea) async {
  final l10n = AppLocalizations.of(context);
  final navegador = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: AppNumbers.paddingStandard),
          Expanded(child: Text(l10n.conectandoBanco)),
        ],
      ),
    ),
  );
  try {
    return await tarea();
  } finally {
    navegador.pop();
  }
}

class _DialogoElegirBanco extends StatefulWidget {
  final List<BancoDisponible> bancos;
  const _DialogoElegirBanco({required this.bancos});

  @override
  State<_DialogoElegirBanco> createState() => _DialogoElegirBancoState();
}

class _DialogoElegirBancoState extends State<_DialogoElegirBanco> {
  final TextEditingController _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consulta = _buscar.text.trim().toLowerCase();
    final visibles = consulta.isEmpty ? widget.bancos : widget.bancos.where((b) => b.nombre.toLowerCase().contains(consulta)).toList();

    return AlertDialog(
      title: Text(l10n.elegirBanco),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _buscar,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.buscarBanco, prefixIcon: const Icon(Icons.search)),
            ),
            const SizedBox(height: AppNumbers.paddingCorto),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: visibles
                    .map((b) => ListTile(
                          dense: true,
                          leading: AvatarBanco(banco: ServicioSincronizacionBancaria.bancoCatalogo(b.nombre), radio: 14),
                          title: Text(b.nombre),
                          onTap: () => Navigator.pop(context, b),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelar))],
    );
  }
}

class _DialogoElegirCuenta extends StatelessWidget {
  final SesionBancaria sesion;
  final CuentaBancaria cuenta;
  const _DialogoElegirCuenta({required this.sesion, required this.cuenta});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.elegirCuentaBanco(cuenta.nombre)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: sesion.cuentas
              .map((c) => ListTile(
                    leading: const Icon(Icons.account_balance),
                    title: Text(c.nombre ?? sesion.banco),
                    subtitle: c.iban == null ? null : Text(Iban.enmascarar(Iban.normalizar(c.iban!))),
                    onTap: () => Navigator.pop(context, c),
                  ))
              .toList(),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelar))],
    );
  }
}
