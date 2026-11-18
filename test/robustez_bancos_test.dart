import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/servicios/open_banking/config_open_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/enable_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';
import 'package:presupuesto_familiar/servicios/open_banking/servicio_sincronizacion_bancaria.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';
import 'package:presupuesto_familiar/servicios/servicio_extractos.dart';

// Casos límite de la conexión con los bancos que pueden darse con un banco real

// Sin clave real: la firma se sustituye
EnableBanking _api(Future<http.Response> Function(http.Request) responder) => EnableBanking(
      idAplicacion: 'app-123',
      clavePrivadaPem: '',
      cliente: MockClient(responder),
      firmarToken: () => 'token',
    );

http.Response _json(Object datos, [int codigo = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(datos)), codigo, headers: {'content-type': 'application/json'});

Map<String, dynamic> _mov(String importe, String indicador, String fecha, {String status = 'BOOK', String? ref, String? concepto}) => {
      'transaction_amount': {'amount': importe, 'currency': 'EUR'},
      'credit_debit_indicator': indicador,
      'status': status,
      'booking_date': fecha,
      'entry_reference': ?ref,
      'remittance_information': [concepto ?? 'MOV $importe'],
    };

Future<ErrorBancario> _error(Future<Object?> Function() llamada) async {
  try {
    await llamada();
  } on ErrorBancario catch (e) {
    return e;
  }
  fail('debería dar un ErrorBancario');
}

// Proveedor configurable para probar la descarga
class _Falso implements ProveedorBancario {
  ErrorBancario? errorSaldo;
  ErrorBancario? Function(DateTime desde)? errorMovimientos;
  final List<DateTime> pedidos = [];
  List<MovimientoExtracto> lista = [];
  int llamadas = 0;

  @override
  TipoProveedor get tipo => TipoProveedor.enableBanking;
  @override
  Future<bool> probarConexion() async => true;
  @override
  Future<List<BancoDisponible>> bancos(String pais) async => [];
  @override
  Future<String> iniciarAutorizacion({required BancoDisponible banco, required String urlVuelta, required String estado, required DateTime validaHasta}) async => '';
  @override
  Future<SesionBancaria> completarAutorizacion(String codigo) async => throw UnimplementedError();
  @override
  Future<SaldoRemoto?> saldo(String cuentaUid) async {
    llamadas++;
    if (errorSaldo != null) throw errorSaldo!;
    return SaldoRemoto(100, DateTime(2026, 11, 17));
  }

  @override
  Future<List<MovimientoExtracto>> movimientos(String cuentaUid, {required DateTime desde}) async {
    llamadas++;
    pedidos.add(desde);
    final error = errorMovimientos?.call(desde);
    if (error != null) throw error;
    return lista;
  }

  @override
  Future<void> cerrarSesion(String sesionId) async {}
}

void main() {
  group('Enable Banking: respuestas raras del banco', () {
    test('solo entran los movimientos contabilizados: pendientes, retenidos, anulados o rechazados no', () async {
      final api = _api((r) async => _json({
            'transactions': [
              _mov('1.00', 'DBIT', '2026-11-10'),
              _mov('2.00', 'DBIT', '2026-11-10', status: 'PDNG'),
              _mov('3.00', 'DBIT', '2026-11-10', status: 'HOLD'),
              _mov('4.00', 'DBIT', '2026-11-10', status: 'CNCL'),
              _mov('5.00', 'DBIT', '2026-11-10', status: 'RJCT'),
              _mov('6.00', 'DBIT', '2026-11-10', status: 'SCHD'),
              _mov('7.00', 'CRDT', '2026-11-11', status: 'OTHR'),
            ],
          }));
      final movimientos = await api.movimientos('u1', desde: DateTime(2026, 11, 1));
      expect(movimientos.map((m) => m.importe), [-1.0, 7.0]);
    });

    test('un movimiento repetido entre páginas (misma referencia) entra una sola vez', () async {
      final api = _api((r) async {
        if (r.url.queryParameters['continuation_key'] == null) {
          return _json({'transactions': [_mov('9.99', 'DBIT', '2026-11-10', ref: 'R1')], 'continuation_key': 'p2'});
        }
        return _json({'transactions': [_mov('9.99', 'DBIT', '2026-11-10', ref: 'R1'), _mov('9.99', 'DBIT', '2026-11-10', ref: 'R2')]});
      });
      final movimientos = await api.movimientos('u1', desde: DateTime(2026, 11, 1));
      expect(movimientos, hasLength(2)); // R1 una vez y R2 (otro café del mismo importe)
    });

    test('si el banco devuelve otra vez la misma clave de página, se para', () async {
      var peticiones = 0;
      final api = _api((r) async {
        peticiones++;
        return _json({'transactions': [], 'continuation_key': 'siempre-la-misma'});
      });
      await api.movimientos('u1', desde: DateTime(2026, 11, 1));
      expect(peticiones, 2);
    });

    test('importes en céntimos exactos, aunque el banco mande signo o pocos decimales', () {
      MovimientoExtracto m(Map<String, dynamic> t) => EnableBanking.movimientoDesdeJson(t)!;
      expect(m(_mov('0.1', 'DBIT', '2026-11-10')).centimos, 10);
      expect(m(_mov('1234.56', 'DBIT', '2026-11-10')).importe, -1234.56);
      expect(m(_mov('19.99', 'DBIT', '2026-11-10')).centimos, 1999);
      // Sin indicador: manda el signo del importe
      final sinIndicador = {..._mov('-8.20', 'DBIT', '2026-11-10')}..remove('credit_debit_indicator');
      expect(m(sinIndicador).importe, -8.2);
      // Con indicador DBIT y signo negativo no se invierte dos veces
      expect(m(_mov('-8.20', 'DBIT', '2026-11-10')).importe, -8.2);
    });

    test('remittance_information como texto suelto y sin fecha contable usa la fecha valor', () {
      final t = {
        'transaction_amount': {'amount': '3.00', 'currency': 'EUR'},
        'credit_debit_indicator': 'DBIT',
        'value_date': '2026-11-09',
        'remittance_information': 'PAGO BIZUM',
      };
      final m = EnableBanking.movimientoDesdeJson(t)!;
      expect(m.concepto, 'PAGO BIZUM');
      expect(m.fecha, DateTime(2026, 11, 9));
    });

    test('una página HTML con 200 (portal cautivo, proxy) da un error bancario', () async {
      final api = _api((r) async => http.Response('<html>Wifi</html>', 200));
      await _error(() => api.saldo('u1'));
    });

    test('sin red da un error bancario legible', () async {
      final api = _api((r) async => throw http.ClientException('Failed host lookup'));
      final e = await _error(() => api.bancos('ES'));
      expect(e.motivo, contains('Sin conexión'));
    });

    test('una sesión sin id o sin cuentas da un error bancario, no un fallo de tipos', () async {
      await _error(() => _api((r) async => _json({'accounts': []})).completarAutorizacion('c'));
      await _error(() => _api((r) async => _json({'session_id': 's1', 'accounts': []})).completarAutorizacion('c'));
    });

    test('bancos sin nombre se ignoran en vez de romper la lista', () async {
      final api = _api((r) async => _json({
            'aspsps': [
              {'country': 'ES'},
              {'name': 'BBVA', 'country': 'ES'},
            ]
          }));
      expect((await api.bancos('ES')).map((b) => b.nombre), ['BBVA']);
    });

    test('la validez del consentimiento va en UTC y sin fracciones de segundo', () async {
      Map<String, dynamic>? cuerpo;
      final api = _api((r) async {
        cuerpo = jsonDecode(r.body);
        return _json({'url': 'https://banco'});
      });
      await api.iniciarAutorizacion(
        banco: const BancoDisponible(nombre: 'BBVA', pais: 'ES'),
        urlVuelta: 'https://x',
        estado: 'e',
        validaHasta: DateTime.utc(2027, 5, 16, 21, 20, 40, 123, 456),
      );
      expect(cuerpo!['access']['valid_until'], '2027-05-16T21:20:40Z');
    });

    test('se reconocen la sesión caducada y el límite de consultas del banco', () async {
      final caducada = await _error(() => _api((r) async => _json({'error': 'EXPIRED_SESSION'}, 400)).saldo('u1'));
      expect(caducada.requiereReconectar, isTrue);
      final limite = await _error(() => _api((r) async => _json({'error': 'ASPSP_RATE_LIMIT_EXCEEDED'}, 429)).saldo('u1'));
      expect(limite.limiteConsultas, isTrue);
      expect(limite.requiereReconectar, isFalse);
      final otro = await _error(() => _api((r) async => _json({'error': 'ASPSP_ERROR'}, 500)).saldo('u1'));
      expect((otro.requiereReconectar, otro.limiteConsultas), (false, false));
    });

    test('ignora saldos sin importe y se queda con el primero válido', () async {
      final api = _api((r) async => _json({
            'balances': [
              {'balance_amount': {'amount': null, 'currency': 'EUR'}, 'balance_type': 'CLBD'},
              {'balance_amount': {'amount': '-15.30', 'currency': 'EUR'}, 'balance_type': 'ITAV'},
            ]
          }));
      expect((await api.saldo('u1'))!.importe, -15.3);
    });
  });

  group('Descarga de una cuenta conectada', () {
    late _Falso falso;
    late CuentaBancaria conectada;
    final hoy = DateTime(2026, 11, 18, 10);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ServicioCuentasAhorro.reasignarMovimientos = (desde, hacia) async {};
      falso = _Falso();
      ServicioExtractos.movimientosExistentes = () async => [];
      ConfigOpenBanking.proveedorDePrueba = () => falso;
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'BBVA', tipo: TipoCuenta.corriente);
      const remota = CuentaRemota(uid: 'u1');
      await ServicioSincronizacionBancaria.enlazar(
        cuenta,
        SesionBancaria(id: 's1', banco: 'BBVA', cuentas: const [remota], validaHasta: DateTime(2027, 5, 1)),
        remota,
      );
      conectada = (await ServicioCuentasAhorro.cargarTodas()).single;
    });
    tearDown(() => ConfigOpenBanking.proveedorDePrueba = null);

    test('si el banco no da saldo, los movimientos se descargan igual', () async {
      falso.errorSaldo = const ErrorBancario('No soportado', codigoHttp: 422);
      falso.lista = [MovimientoExtracto(fecha: DateTime(2026, 11, 17), concepto: 'X', importe: -1)];
      final extracto = await ServicioSincronizacionBancaria.descargar(conectada, ahora: hoy);
      expect(extracto.saldoFinal, isNull);
      expect(extracto.movimientos, hasLength(1));
    });

    test('si el saldo dice que la sesión caducó, se avisa para reconectar', () async {
      falso.errorSaldo = const ErrorBancario('x', codigoHttp: 401, codigo: 'EXPIRED_SESSION');
      expect(
        () => ServicioSincronizacionBancaria.descargar(conectada, ahora: hoy),
        throwsA(isA<ErrorBancario>().having((e) => e.requiereReconectar, 'reconectar', isTrue)),
      );
    });

    test('si el banco no admite 90 días de historial, se reintenta con 30', () async {
      falso.errorMovimientos = (desde) => desde.isBefore(DateTime(2026, 10, 1))
          ? const ErrorBancario('x', codigoHttp: 422, codigo: ErrorBancario.codigoPeriodoNoValido)
          : null;
      await ServicioSincronizacionBancaria.descargar(conectada, ahora: hoy);
      expect(falso.pedidos, [DateTime(2026, 8, 20, 10), DateTime(2026, 10, 19)]);
    });

    test('con el consentimiento vencido no se llama al banco', () async {
      await expectLater(
        ServicioSincronizacionBancaria.descargar(conectada, ahora: DateTime(2027, 6, 1)),
        throwsA(isA<ErrorBancario>().having((e) => e.requiereReconectar, 'reconectar', isTrue)),
      );
      expect(falso.llamadas, 0);
    });

    test('si todo lo descargado ya está en el presupuesto no hay nada nuevo', () async {
      ServicioExtractos.movimientosExistentes = () async => [
            Transaccion(montoEnCentimos: 1250, concepto: 'MERCADONA', fecha: DateTime(2026, 11, 16), categoria: 'General', esIngreso: false, tarroDestino: 'Cuenta Mensual'),
          ];
      final repetido = ExtractoCuenta(movimientos: [MovimientoExtracto(fecha: DateTime(2026, 11, 17), concepto: 'COMPRA MERCADONA', importe: -12.5)]);
      final nuevo = ExtractoCuenta(movimientos: [MovimientoExtracto(fecha: DateTime(2026, 11, 17), concepto: 'RENFE', importe: -20)]);
      expect(await ServicioSincronizacionBancaria.nadaNuevo(repetido), isTrue);
      expect(await ServicioSincronizacionBancaria.nadaNuevo(nuevo), isFalse);
      expect(await ServicioSincronizacionBancaria.nadaNuevo(const ExtractoCuenta(movimientos: [])), isTrue);
    });
  });
}
