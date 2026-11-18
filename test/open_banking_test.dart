import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/l10n/app_localizations.dart';
import 'package:presupuesto_familiar/modelos/extracto.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_conexion_bancos.dart';
import 'package:presupuesto_familiar/pantallas/pantalla_importar_extracto.dart';
import 'package:presupuesto_familiar/servicios/servicio_extractos.dart';
import 'package:presupuesto_familiar/servicios/open_banking/config_open_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/enable_banking.dart';
import 'package:presupuesto_familiar/servicios/open_banking/proveedor_bancario.dart';
import 'package:presupuesto_familiar/servicios/open_banking/servicio_sincronizacion_bancaria.dart';
import 'package:presupuesto_familiar/servicios/servicio_cuentas_ahorro.dart';

// Clave RSA de prueba (solo para los tests; no corresponde a ninguna aplicación real)
const _clavePrivada = """-----BEGIN PRIVATE KEY-----
MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBALzmsbMB/5P7Q3dl
uQIbnr4RLYBaa6hz3IFHHycHAsp2qWV0LQDCVeXzFICsza55Ts6MXZ0G5TeYZCTS
wWlopo4oEqwOGEyqC5rj2d2MNUiydIWwdg7rPclQdn6Cedgr2rLcxkFZO2NjpMvX
jan5uY594PKpLCTFcxL5KC9qac27AgMBAAECgYAF0cmZrS8VfQEoFX8snHM4gcj4
ElEMwH0DkpBYIHQqjptLX9ffFR2WVvXDvQ8dF+mgnVxo8QRwwQYcyE1jFPFElEve
Omq9AULSvZd/gHH0fC0HJzsghy6/ZoL7noMkKVECte8bIVJ/3DvN9Yp8b0xvqlgv
CdEi9vMx2UdL+Ft9KQJBAOxA/4lcGKsHStY+VLSX6OIZMjjEK2aVIyrTAbNKAuYU
J+6VY0EXR9MgkiOtQcrlPLpm6B1iHAm4bYuNFaJHEuUCQQDMsIOHBZBuHIfKYC6y
qMtyVhXwXlxxGOp09saKnvKBGBGYHrpIn7XIGGzB5PmEjzhuq3Fgh575lcY1Skzs
mDQfAkB9sC7Csv5kruJ/jHWgBlldQC5ZyPOWBa3J8Kws6CkWoo6D/XHqhSovBlr5
JAmmmcJvIKRITZPBEB8naQ2jYdCJAkADXR88N84w0Q02OTBrRTTasyl3IsXYIfWw
aGHI42XO00tuuYqMKPu+xw/6e73R/NyLjQu272OgbGKue4MaHEI3AkEAqshgauko
kA9IJiq+CKwa9UGHGkPYMSiwx8eMFYgoYUDKnjKlQ/xM7Z98XW389iygs8H3jEK2
Uh949zDlHnFA9w==
-----END PRIVATE KEY-----""";
const _clavePublica = """-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC85rGzAf+T+0N3ZbkCG56+ES2A
Wmuoc9yBRx8nBwLKdqlldC0AwlXl8xSArM2ueU7OjF2dBuU3mGQk0sFpaKaOKBKs
DhhMqgua49ndjDVIsnSFsHYO6z3JUHZ+gnnYK9qy3MZBWTtjY6TL142p+bmOfeDy
qSwkxXMS+SgvamnNuwIDAQAB
-----END PUBLIC KEY-----""";

EnableBanking _api(Future<http.Response> Function(http.Request) responder) => EnableBanking(
      idAplicacion: 'app-123',
      clavePrivadaPem: _clavePrivada,
      cliente: MockClient(responder),
    );

http.Response _json(Object datos, [int codigo = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(datos)), codigo, headers: {'content-type': 'application/json'});

class _ProveedorFalso implements ProveedorBancario {
  DateTime? pedidoDesde;
  String? sesionCerrada;

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
  Future<SaldoRemoto?> saldo(String cuentaUid) async => SaldoRemoto(1234.5, DateTime(2026, 11, 4));
  @override
  Future<List<MovimientoExtracto>> movimientos(String cuentaUid, {required DateTime desde}) async {
    pedidoDesde = desde;
    return [];
  }
  @override
  Future<void> cerrarSesion(String sesionId) async => sesionCerrada = sesionId;
}

void main() {
  group('Enable Banking', () {
    test('firma el JWT con RS256, el id de la aplicación como kid y las claims que pide la API', () async {
      String? autorizacion;
      final api = _api((r) async {
        autorizacion = r.headers['Authorization'];
        return _json({'aspsps': []});
      });
      await api.bancos('ES');
      final token = autorizacion!.substring('Bearer '.length);
      final jwt = JWT.verify(token, RSAPublicKey(_clavePublica), checkHeaderType: true);
      expect(jwt.header?['kid'], 'app-123');
      expect(jwt.header?['alg'], 'RS256');
      expect(jwt.payload['iss'], 'enablebanking.com');
      expect(jwt.payload['aud'], 'api.enablebanking.com');
      final duracion = (jwt.payload['exp'] as int) - (jwt.payload['iat'] as int);
      expect(duracion, lessThanOrEqualTo(86400));
    });

    test('una clave privada no válida da un error bancario, no una excepción cualquiera', () async {
      final api = EnableBanking(idAplicacion: 'x', clavePrivadaPem: 'no es una clave', cliente: MockClient((_) async => _json({})));
      expect(() => api.bancos('ES'), throwsA(isA<ErrorBancario>()));
    });

    test('lista los bancos del país, ordenados y con la validez máxima en días', () async {
      Uri? pedida;
      final api = _api((r) async {
        pedida = r.url;
        return _json({
          'aspsps': [
            {'name': 'Openbank', 'country': 'ES', 'logo': 'https://x/o.png', 'maximum_consent_validity': 15552000},
            {'name': 'BBVA', 'country': 'ES'},
          ]
        });
      });
      final bancos = await api.bancos('ES');
      expect(pedida!.path, '/aspsps');
      expect(pedida!.queryParameters['country'], 'ES');
      expect(bancos.map((b) => b.nombre), ['BBVA', 'Openbank']);
      expect(bancos.last.diasConsentimientoMax, 180);
      expect(bancos.first.diasConsentimientoMax, 90);
    });

    test('inicia la autorización con banco, URL de vuelta, estado y validez', () async {
      Map<String, dynamic>? cuerpo;
      final api = _api((r) async {
        cuerpo = jsonDecode(r.body);
        return _json({'url': 'https://banco/autoriza', 'authorization_id': 'a1'});
      });
      final url = await api.iniciarAutorizacion(
        banco: const BancoDisponible(nombre: 'Openbank', pais: 'ES'),
        urlVuelta: 'https://mi.web/banco',
        estado: 'abc',
        validaHasta: DateTime.utc(2027, 5, 1),
      );
      expect(url, 'https://banco/autoriza');
      expect(cuerpo!['aspsp'], {'name': 'Openbank', 'country': 'ES'});
      expect(cuerpo!['redirect_url'], 'https://mi.web/banco');
      expect(cuerpo!['state'], 'abc');
      expect(cuerpo!['psu_type'], 'personal');
      expect(cuerpo!['access']['valid_until'], startsWith('2027-05-01T00:00:00'));
    });

    test('completa la sesión con las cuentas autorizadas', () async {
      final api = _api((r) async => _json({
            'session_id': 's1',
            'aspsp': {'name': 'Openbank', 'country': 'ES'},
            'access': {'valid_until': '2027-05-01T00:00:00+00:00'},
            'accounts': [
              {'uid': 'u1', 'account_id': {'iban': 'ES9121000418450200051332'}, 'name': 'Cuenta Nómina', 'currency': 'EUR'},
            ],
          }));
      final sesion = await api.completarAutorizacion('code');
      expect(sesion.id, 's1');
      expect(sesion.banco, 'Openbank');
      expect(sesion.validaHasta, DateTime.utc(2027, 5, 1));
      expect(sesion.cuentas.single.uid, 'u1');
      expect(sesion.cuentas.single.iban, 'ES9121000418450200051332');
    });

    test('elige el saldo contable antes que el disponible', () async {
      final api = _api((r) async => _json({
            'balances': [
              {'balance_amount': {'amount': '90.00', 'currency': 'EUR'}, 'balance_type': 'ITAV'},
              {'balance_amount': {'amount': '100.50', 'currency': 'EUR'}, 'balance_type': 'CLBD', 'reference_date': '2026-11-04'},
            ]
          }));
      final saldo = await api.saldo('u1');
      expect(saldo!.importe, 100.5);
      expect(saldo.fecha, DateTime(2026, 11, 4));
    });

    test('descarga todas las páginas de movimientos y convierte signo, fecha y concepto', () async {
      final pedidas = <Uri>[];
      final api = _api((r) async {
        pedidas.add(r.url);
        if (r.url.queryParameters['continuation_key'] == null) {
          return _json({
            'transactions': [
              {
                'transaction_amount': {'amount': '12.50', 'currency': 'EUR'},
                'credit_debit_indicator': 'DBIT',
                'status': 'BOOK',
                'booking_date': '2026-11-02',
                'creditor': {'name': 'MERCADONA'},
                'remittance_information': ['COMPRA TARJ. MERCADONA VALENCIA'],
              },
              {
                'transaction_amount': {'amount': '5.00', 'currency': 'EUR'},
                'credit_debit_indicator': 'DBIT',
                'status': 'PDNG',
                'booking_date': '2026-11-03',
              },
            ],
            'continuation_key': 'pag2',
          });
        }
        return _json({
          'transactions': [
            {
              'transaction_amount': {'amount': '1500.00', 'currency': 'EUR'},
              'credit_debit_indicator': 'CRDT',
              'status': 'BOOK',
              'value_date': '2026-10-31',
              'debtor': {'name': 'EMPRESA SL'},
              'remittance_information': ['NOMINA OCTUBRE'],
            },
          ],
        });
      });
      final movimientos = await api.movimientos('u1', desde: DateTime(2026, 10, 1));
      expect(pedidas.first.path, '/accounts/u1/transactions');
      expect(pedidas.first.queryParameters['date_from'], '2026-10-01');
      expect(pedidas.last.queryParameters['continuation_key'], 'pag2');
      // Ordenados por fecha; el pendiente no entra
      expect(movimientos.map((m) => m.importe), [1500, -12.5]);
      expect(movimientos.first.concepto, 'EMPRESA SL NOMINA OCTUBRE');
      expect(movimientos.first.fecha, DateTime(2026, 10, 31));
      // El nombre ya está dentro de la remesa: no se repite
      expect(movimientos.last.concepto, 'COMPRA TARJ. MERCADONA VALENCIA');
    });

    test('un 401 se marca como consentimiento caducado', () async {
      final api = _api((r) async => _json({'error': 'EXPIRED_SESSION', 'message': 'Session expired'}, 401));
      try {
        await api.saldo('u1');
        fail('debería fallar');
      } on ErrorBancario catch (e) {
        expect(e.requiereReconectar, isTrue);
        expect(e.motivo, contains('EXPIRED_SESSION'));
      }
    });
  });

  group('URL de vuelta', () {
    test('saca el código de la dirección pegada', () {
      expect(codigoDeUrlVuelta('https://mi.web/banco?state=abc&code=xyz', estadoEsperado: 'abc'), 'xyz');
      expect(codigoDeUrlVuelta('  xyz-123  '), 'xyz-123');
    });

    test('rechaza errores, estados cruzados y direcciones sin código', () {
      expect(codigoDeUrlVuelta('https://mi.web/banco?error=access_denied&state=abc'), isNull);
      expect(codigoDeUrlVuelta('https://mi.web/banco?state=otro&code=xyz', estadoEsperado: 'abc'), isNull);
      expect(codigoDeUrlVuelta('https://mi.web/banco'), isNull);
      expect(codigoDeUrlVuelta(''), isNull);
    });
  });

  group('Sincronización', () {
    late _ProveedorFalso falso;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ServicioCuentasAhorro.reasignarMovimientos = (desde, hacia) async {};
      falso = _ProveedorFalso();
      ConfigOpenBanking.proveedorDePrueba = () => falso;
    });
    tearDown(() => ConfigOpenBanking.proveedorDePrueba = null);

    SesionBancaria sesion(List<CuentaRemota> cuentas) =>
        SesionBancaria(id: 's1', banco: 'Openbank', cuentas: cuentas, validaHasta: DateTime(2027, 5, 1));

    test('enlaza por IBAN, guarda el enlace y lo conserva al recargar', () async {
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'Openbank', tipo: TipoCuenta.corriente, iban: 'ES91 2100 0418 4502 0005 1332');
      final s = sesion(const [
        CuentaRemota(uid: 'otra', iban: 'ES7921000813610123456789'),
        CuentaRemota(uid: 'u1', iban: 'ES9121000418450200051332'),
      ]);
      final remota = ServicioSincronizacionBancaria.cuentaCorrespondiente(s, cuenta)!;
      expect(remota.uid, 'u1');
      await ServicioSincronizacionBancaria.enlazar(cuenta, s, remota);
      final guardada = (await ServicioCuentasAhorro.cargarTodas()).single;
      expect(guardada.conectada, isTrue);
      expect(guardada.enlace!.cuentaUid, 'u1');
      expect(guardada.enlace!.validaHasta, DateTime(2027, 5, 1));
      expect(guardada.enlace!.caducado(DateTime(2027, 6, 1)), isTrue);
    });

    test('con varias cuentas y ninguna coincide, hay que preguntar', () async {
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'Openbank', tipo: TipoCuenta.corriente);
      final s = sesion(const [CuentaRemota(uid: 'a'), CuentaRemota(uid: 'b')]);
      expect(ServicioSincronizacionBancaria.cuentaCorrespondiente(s, cuenta), isNull);
      expect(ServicioSincronizacionBancaria.cuentaCorrespondiente(sesion(const [CuentaRemota(uid: 'a')]), cuenta)!.uid, 'a');
    });

    test('la primera descarga pide 90 días; las siguientes, desde la última con solape', () async {
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'Openbank', tipo: TipoCuenta.corriente);
      await ServicioSincronizacionBancaria.enlazar(cuenta, sesion(const [CuentaRemota(uid: 'u1')]), const CuentaRemota(uid: 'u1'));
      var conectada = (await ServicioCuentasAhorro.cargarTodas()).single;
      final hoy = DateTime(2026, 11, 5);

      final extracto = await ServicioSincronizacionBancaria.descargar(conectada, ahora: hoy);
      expect(falso.pedidoDesde, DateTime(2026, 8, 7));
      expect(extracto.saldoFinal, 1234.5);

      await ServicioSincronizacionBancaria.marcarSincronizada(conectada, cuando: hoy);
      conectada = (await ServicioCuentasAhorro.cargarTodas()).single;
      await ServicioSincronizacionBancaria.descargar(conectada, ahora: DateTime(2026, 11, 20));
      expect(falso.pedidoDesde, DateTime(2026, 10, 29));
    });

    test('al desconectar se quita el enlace y se revoca la sesión si nadie más la usa', () async {
      final a = await ServicioCuentasAhorro.anadir('A', 'Openbank', tipo: TipoCuenta.corriente);
      final b = await ServicioCuentasAhorro.anadir('B', 'Openbank');
      final s = sesion(const [CuentaRemota(uid: 'u1'), CuentaRemota(uid: 'u2')]);
      await ServicioSincronizacionBancaria.enlazar(a, s, s.cuentas[0]);
      await ServicioSincronizacionBancaria.enlazar(b, s, s.cuentas[1]);
      var cuentas = await ServicioCuentasAhorro.cargarTodas();

      await ServicioSincronizacionBancaria.desconectar(cuentas.first);
      expect(falso.sesionCerrada, isNull); // B sigue usándola
      cuentas = await ServicioCuentasAhorro.cargarTodas();
      expect(cuentas.first.conectada, isFalse);

      await ServicioSincronizacionBancaria.desconectar(cuentas.last);
      expect(falso.sesionCerrada, 's1');
    });

    test('pone primero los bancos que se parecen al de la cuenta', () async {
      final cuenta = await ServicioCuentasAhorro.anadir('Nómina', 'CaixaBank', tipo: TipoCuenta.corriente, bancoId: 'caixabank');
      final ordenados = ServicioSincronizacionBancaria.ordenarPara(const [
        BancoDisponible(nombre: 'BBVA', pais: 'ES'),
        BancoDisponible(nombre: 'Caixabank', pais: 'ES'),
      ], cuenta);
      expect(ordenados.first.nombre, 'Caixabank');
      expect(ServicioSincronizacionBancaria.bancoCatalogo('Banco Santander')?.id, 'santander');
    });
  });

  group('Pantallas', () {
    Widget app(Widget hijo) => MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.idiomasSoportados,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: hijo,
        );

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('la configuración guarda proveedor, credenciales y URL de vuelta', (tester) async {
      await tester.pumpWidget(app(const PantallaConexionBancos()));
      await tester.pumpAndSettle();
      expect(find.text('Enable Banking'), findsOneWidget);
      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), ' app-123 ');
      await tester.enterText(campos.at(1), 'PEM');
      await tester.enterText(campos.at(2), 'https://mi.web/banco');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(ConfigOpenBanking.idAplicacion, 'app-123');
      expect(ConfigOpenBanking.configurada, isTrue);
      await ConfigOpenBanking.cargar();
      expect(ConfigOpenBanking.urlVuelta, 'https://mi.web/banco');
      expect(ConfigOpenBanking.pais, 'ES');
    });

    testWidgets('al sincronizar vienen marcados los movimientos nuevos y no los ya importados', (tester) async {
      final ya = MovimientoExtracto(fecha: DateTime(2026, 11, 2), concepto: 'MERCADONA', importe: -12.5);
      ServicioExtractos.movimientosExistentes = () async => [
            Transaccion(montoEnCentimos: 1250, concepto: 'MERCADONA', fecha: DateTime(2026, 11, 2), categoria: 'Supermercado', esIngreso: false, tarroDestino: 'Cuenta Mensual'),
          ];
      final extracto = ExtractoCuenta(movimientos: [ya, MovimientoExtracto(fecha: DateTime(2026, 11, 3), concepto: 'RENFE', importe: -20)]);
      await tester.pumpWidget(app(PantallaImportarExtracto(
        cuenta: const CuentaBancaria(id: '1', nombre: 'Nómina', tipo: TipoCuenta.corriente),
        extracto: extracto,
        preseleccionar: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Importar 1'), findsOneWidget);
    });
  });

  group('Duplicados entre notificaciones y banco', () {
    Transaccion gasto(String concepto, int centimos, DateTime fecha) => Transaccion(
        montoEnCentimos: centimos, concepto: concepto, fecha: fecha, categoria: 'General', esIngreso: false, tarroDestino: 'Cuenta Mensual');
    MovimientoExtracto cargo(String concepto, double importe, DateTime fecha) =>
        MovimientoExtracto(fecha: fecha, concepto: concepto, importe: -importe);

    test('el gasto apuntado por notificación cubre el cargo del banco días después', () {
      final existentes = [gasto('MERCADONA', 1250, DateTime(2026, 11, 2, 13, 40))];
      final banco = [
        cargo('COMPRA TARJ. MERCADONA VALENCIA', 12.5, DateTime(2026, 11, 4)),
        cargo('RECIBO IBERDROLA', 45.3, DateTime(2026, 11, 4)),
      ];
      expect(ServicioExtractos.indicesYaImportados(banco, existentes, margenDias: 3), {0});
      // Sin margen (importar un fichero) se mantiene la regla exacta de siempre
      expect(ServicioExtractos.indicesYaImportados(banco, existentes), isEmpty);
    });

    test('más de 3 días, otro importe o un ingreso no cuentan', () {
      final existentes = [gasto('MERCADONA', 1250, DateTime(2026, 11, 1))];
      expect(ServicioExtractos.indicesYaImportados([cargo('MERCADONA', 12.5, DateTime(2026, 11, 5))], existentes, margenDias: 3), isEmpty);
      expect(ServicioExtractos.indicesYaImportados([cargo('MERCADONA', 12.4, DateTime(2026, 11, 2))], existentes, margenDias: 3), isEmpty);
      expect(
        ServicioExtractos.indicesYaImportados([MovimientoExtracto(fecha: DateTime(2026, 11, 2), concepto: 'X', importe: 12.5)], existentes, margenDias: 3),
        isEmpty,
      );
    });

    test('cada apunte cubre un solo cargo: dos cafés iguales con un solo apunte dejan uno nuevo', () {
      final existentes = [gasto('Café', 150, DateTime(2026, 11, 3))];
      final banco = [cargo('CAFETERIA SOL', 1.5, DateTime(2026, 11, 2)), cargo('CAFETERIA SOL', 1.5, DateTime(2026, 11, 3))];
      // Se empareja con el de fecha más cercana
      expect(ServicioExtractos.indicesYaImportados(banco, existentes, margenDias: 3), {1});
    });

    test('un apunte que ya coincide exacto no cubre además otro cargo', () {
      final existentes = [gasto('CAFETERIA SOL', 150, DateTime(2026, 11, 3))];
      final banco = [cargo('CAFETERIA SOL', 1.5, DateTime(2026, 11, 3)), cargo('BAR', 1.5, DateTime(2026, 11, 4))];
      expect(ServicioExtractos.indicesYaImportados(banco, existentes, margenDias: 3), {0});
    });
  });
}
