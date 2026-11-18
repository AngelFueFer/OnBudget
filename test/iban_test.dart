import 'package:flutter_test/flutter_test.dart';

import 'package:presupuesto_familiar/constants/catalogo_bancos.dart';
import 'package:presupuesto_familiar/utilidades/iban.dart';

void main() {
  group('Iban', () {
    test('acepta IBAN válidos con espacios y minúsculas', () {
      expect(Iban.esValido('ES91 2100 0418 4502 0005 1332'), isTrue);
      expect(Iban.esValido('es7921000813610123456789'), isTrue);
      expect(Iban.esValido('DE89 3704 0044 0532 0130 00'), isTrue);
    });

    test('rechaza control incorrecto, longitud del país o CCC incorrecto', () {
      expect(Iban.esValido('ES9221000418450200051332'), isFalse); // control IBAN
      expect(Iban.esValido('ES912100041845020005133'), isFalse); // falta un dígito
      expect(Iban.cccValido('ES9121000418450200051332'), isTrue);
      expect(Iban.cccValido('ES9121000418460200051332'), isFalse); // DC del CCC
      expect(Iban.esValido(''), isFalse);
    });

    test('código de banco por país', () {
      expect(Iban.codigoBanco('ES9121000418450200051332'), '2100');
      expect(Iban.codigoBanco('DE89370400440532013000'), '37040044');
      expect(Iban.codigoBanco('NL91BUNQ0417164300'), 'BUNQ');
      expect(Iban.codigoBanco('XX00'), isNull);
    });

    test('formatea en grupos de 4 y enmascara', () {
      expect(Iban.formatear('ES9121000418450200051332'), 'ES91 2100 0418 4502 0005 1332');
      expect(Iban.enmascarar('ES9121000418450200051332'), 'ES91 •••• •••• •••• •••• 1332');
    });
  });

  group('CatalogoBancos', () {
    test('tiene 30 bancos tradicionales y 10 neobancos con ids únicos', () {
      expect(CatalogoBancos.tradicionales, hasLength(30));
      expect(CatalogoBancos.neobancos, hasLength(10));
      expect(CatalogoBancos.bancos.map((b) => b.id).toSet(), hasLength(40));
    });

    test('ningún código de banco está repetido', () {
      final codigos = CatalogoBancos.bancos.expand((b) => b.codigos).toList();
      expect(codigos.toSet(), hasLength(codigos.length));
    });

    test('detecta el banco por el IBAN', () {
      expect(CatalogoBancos.detectar('ES9121000418450200051332')!.id, 'caixabank');
      expect(CatalogoBancos.detectar('ES5700490418950200051332')!.id, 'santander');
      expect(CatalogoBancos.detectar('ES0901820418750200051332')!.id, 'bbva');
      expect(CatalogoBancos.detectar('ES9614650418350200051332')!.id, 'ing');
      expect(CatalogoBancos.detectar('ES7715830418550200051332')!.id, 'revolut');
      expect(CatalogoBancos.detectar('NL91BUNQ0417164300')!.id, 'bunq');
      // Basta con que esté escrito el código de entidad
      expect(CatalogoBancos.detectar('ES00 0182')!.id, 'bbva');
      expect(CatalogoBancos.detectar('ES00 9999'), isNull);
    });

    test('busca sin tildes ni mayúsculas, también por alias', () {
      expect(CatalogoBancos.buscar('la caixa').map((b) => b.id), contains('caixabank'));
      expect(CatalogoBancos.buscar('SABADELL').single.id, 'sabadell');
      expect(CatalogoBancos.buscar('pollenca').single.id, 'colonya');
      expect(CatalogoBancos.buscar(''), hasLength(40));
    });
  });
}
