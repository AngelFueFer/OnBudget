import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presupuesto_familiar/constants/db_keys.dart';
import 'package:presupuesto_familiar/modelos/transaccion.dart';
import 'package:presupuesto_familiar/servicios/detector_pagos.dart';
import 'package:presupuesto_familiar/servicios/detector_tarjetas.dart';
import 'package:presupuesto_familiar/servicios/servicio_notificaciones.dart';
import 'package:presupuesto_familiar/servicios/servicio_pagos_detectados.dart';

// Formatos de notificación de bancos reales (aproximados: los bancos no los publican) y repeticiones
void main() {
  const bbva = 'com.bbva.bbvacontigo';
  const santander = 'es.bancosantander.apps';
  const caixa = 'es.lacaixa.mobile.android.newwapicon';
  const ing = 'www.ingdirect.nativeframe';
  const openbank = 'es.openbank.mobile';
  const revolut = 'com.revolut.revolut';
  const n26 = 'de.number26.android';
  final ahora = DateTime(2026, 11, 18, 9, 30);

  (double, String, String?)? leer(String paquete, String titulo, String texto) {
    final p = DetectorPagos.detectar(paquete, titulo, texto, ahora: ahora);
    return p == null ? null : (p.importe, p.comercio, p.ultimos4);
  }

  group('Lectura de notificaciones de pago', () {
    test('formatos habituales de bancos españoles', () {
      expect(leer(santander, 'Santander', 'Compra con tarjeta terminada en 1234 en MERCADONA por 12,50 EUR'), (12.5, 'MERCADONA', '1234'));
      expect(leer(caixa, 'CaixaBank', 'Compra con tarjeta ...1234 por 12,50 EUR en MERCADONA'), (12.5, 'MERCADONA', '1234'));
      expect(leer(ing, 'Pago con tarjeta', 'Has pagado 12,50 € en MERCADONA'), (12.5, 'MERCADONA', null));
      expect(leer(openbank, 'Openbank', 'Compra de 12,50€ en MERCADONA con tu tarjeta *1234'), (12.5, 'MERCADONA', '1234'));
      expect(leer(bbva, 'BBVA', 'Compra en MERCADONA, VALENCIA de 12,50 €'), (12.5, 'MERCADONA', null));
    });

    test('importes con miles, sin decimales y con espacios especiales antes del €', () {
      expect(leer(bbva, 'BBVA', 'Compra de 1.234,56 € en EL CORTE INGLES')?.$1, 1234.56);
      expect(leer(bbva, 'BBVA', 'Compra de 20 € en BAR PEPE'), (20.0, 'BAR PEPE', null));
      expect(leer(bbva, 'BBVA', 'Pago de 12,50 € en MERCADONA')?.$1, 12.5); // espacio duro
      expect(leer(bbva, 'BBVA', 'Compra de 12,50 € en AMAZON.ES'), (12.5, 'AMAZON.ES', null)); // espacio fino
      expect(leer(revolut, 'Payment', 'You spent €1,234.00 at Apple Store')?.$1, 1234.0);
      final pago = DetectorPagos.detectar(bbva, 'BBVA', 'Compra de 19,99 € en NETFLIX', ahora: ahora)!;
      expect(pago.centimos, 1999);
    });

    test('el comercio sale del título, del texto o del recibo cuando no hay "en"', () {
      expect(leer(revolut, 'MERCADONA', 'Has pagado 12,50 € con tu tarjeta'), (12.5, 'MERCADONA', null));
      expect(leer(bbva, 'Compra con tarjeta', 'MERCADONA 12,50 €'), (12.5, 'MERCADONA', null));
      expect(leer(bbva, 'BBVA', 'Cargo de 45,20 € del recibo de IBERDROLA'), (45.2, 'IBERDROLA', null));
      expect(leer(n26, 'N26', '-12,50 € bei REWE'), (12.5, 'REWE', null));
    });

    test('el saldo que viene detrás no se confunde con el importe', () {
      expect(leer(bbva, 'BBVA', 'Compra de 12,50 € en MERCADONA. Saldo disponible: 1.000,00 €')?.$1, 12.5);
    });

    test('no son gastos: rechazadas, devoluciones, ingresos ni avisos de saldo negativo', () {
      expect(leer(bbva, 'BBVA', 'Compra rechazada de 12,50 € en MERCADONA'), isNull);
      expect(leer(bbva, 'BBVA', 'Operación denegada: pago de 30,00 € en ZARA'), isNull);
      expect(leer(bbva, 'BBVA', 'Devolución de 12,50 € de AMAZON'), isNull);
      expect(leer(bbva, 'BBVA', 'Tu saldo es -50,00 €'), isNull);
      expect(leer(bbva, 'BBVA', 'Has recibido un Bizum de 15,00 € de Ana'), isNull);
      expect(leer(bbva, 'BBVA', 'Tienes una nueva oferta'), isNull);
    });

    test('los últimos 4 dígitos con puntos, asterisco o puntos suspensivos', () {
      expect(DetectorTarjetas.ultimosDigitos('tarjeta ...1234'), '1234');
      expect(DetectorTarjetas.ultimosDigitos('tarjeta …1234'), '1234');
      expect(DetectorTarjetas.ultimosDigitos('tarjeta *1234'), '1234');
      expect(DetectorTarjetas.ultimosDigitos('Visa ••5678'), '5678');
      expect(DetectorTarjetas.ultimosDigitos('Compra de 1.234,56 €'), isNull);
    });
  });

  group('Pagos repetidos', () {
    late List<Transaccion> guardadas;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      guardadas = [];
      ServicioPagosDetectados.insertar = (t) async => guardadas.add(t);
    });

    PagoDetectado pago(DateTime cuando, {double importe = 12.5}) =>
        PagoDetectado(fecha: cuando, importe: importe, comercio: 'MERCADONA', bancoId: 'bbva');

    test('la misma notificación vuelta a publicar a los 2 minutos no se propone otra vez', () async {
      expect(await ServicioPagosDetectados.anadir(pago(ahora)), isTrue);
      expect(await ServicioPagosDetectados.anadir(pago(ahora.add(const Duration(minutes: 2)))), isFalse);
      // Otra compra igual al cabo de una hora sí es un pago nuevo
      expect(await ServicioPagosDetectados.anadir(pago(ahora.add(const Duration(hours: 1)))), isTrue);
      // Otro importe tampoco es el mismo
      expect(await ServicioPagosDetectados.anadir(pago(ahora, importe: 3)), isTrue);
    });

    test('un pago confirmado o descartado no vuelve si el banco repite la notificación', () async {
      final p = pago(ahora);
      await ServicioPagosDetectados.anadir(p);
      await ServicioPagosDetectados.confirmar(p);
      expect(await ServicioPagosDetectados.anadir(p), isFalse);
      expect(await ServicioPagosDetectados.anadir(pago(ahora.add(const Duration(minutes: 1)))), isFalse);

      final otro = pago(ahora, importe: 7);
      await ServicioPagosDetectados.anadir(otro);
      await ServicioPagosDetectados.descartar(otro);
      expect(await ServicioPagosDetectados.anadir(otro), isFalse);
      expect(guardadas, hasLength(1));
    });

    test('un doble toque en confirmar crea el gasto una sola vez', () async {
      final p = pago(ahora);
      await ServicioPagosDetectados.anadir(p);
      await Future.wait([ServicioPagosDetectados.confirmar(p), ServicioPagosDetectados.confirmar(p)]);
      await ServicioPagosDetectados.confirmar(p);
      expect(guardadas, hasLength(1));
      expect(guardadas.single.montoEnCentimos, 1250);
      expect(guardadas.single.esIngreso, isFalse);
    });

    test('datos guardados dañados no impiden arrancar: se ignoran las entradas rotas', () async {
      SharedPreferences.setMockInitialValues({
        DBKeys.pagosDetectados: '[{"fecha":"2026-11-18T09:30:00.000","importe":12.5,"comercio":"BAR","bancoId":"bbva"},{"roto":true}]',
        DBKeys.pagosGestionados: 'no es json',
      });
      expect((await ServicioPagosDetectados.cargar()).single.comercio, 'BAR');
      expect(await ServicioPagosDetectados.anadir(pago(ahora)), isTrue);
    });
  });

  test('se procesa un pago que llega de la bandeja nativa con la hora de la notificación', () async {
    SharedPreferences.setMockInitialValues({});
    final llegada = DateTime(2026, 11, 18, 8, 15);
    await ServicioNotificaciones.procesar(bbva, 'BBVA', 'Compra de 4,20 € en CAFETERIA SOL', fecha: llegada);
    final pendiente = (await ServicioPagosDetectados.cargar()).single;
    expect((pendiente.importe, pendiente.comercio, pendiente.fecha), (4.2, 'CAFETERIA SOL', llegada));
  });
}
