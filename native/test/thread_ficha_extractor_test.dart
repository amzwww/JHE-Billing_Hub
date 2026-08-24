import 'package:bills_maker/utils/thread_ficha_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extrae una ficha completa desde bloques con etiquetas', () {
    final values = extractCommunicationFicha('''
**PERSONA DE CONTACTO**:
Pilar López Navasa
682 872 042
pilarlopez@qmscomunicacion.com

**DATOS FISCALES O DE FACTURACIÓN**:
QMS COMUNICACIÓN
C/ Colombia 64 7A 28016 Madrid
CIF: B- 83567529

**Población de la ponencia: Madrid**
**Importe**: 6000€
''');

    expect(values['company'], 'QMS COMUNICACIÓN');
    expect(values['contact'], 'Pilar López Navasa');
    expect(values['email'], 'pilarlopez@qmscomunicacion.com');
    expect(values['phone'], '682 872 042');
    expect(values['population'], 'Madrid');
    expect(values['amount'], '6000');
    expect(values['tax_company'], 'QMS COMUNICACIÓN');
    expect(values['tax_id'], 'B-83567529');
    expect(values['tax_address'], 'C/ Colombia 64 7A');
    expect(values['tax_postal'], '28016');
    expect(values['tax_population'], 'Madrid');
    expect(values['tax_province'], 'Madrid');
  });

  test('encuentra los mismos datos dentro del hilo real de Gmail', () {
    final values = extractCommunicationFicha('''
Pilar López a través de antispam.mailspamprotection.com
lun, 13 jul, 9:14
para Jon, Pablo, Iban, Rosa, Hola

Confirmarte que tenemos el OK al fee de 6.000€ más gastos de viaje.
Así que vamos adelante para que puedas agendarte el día 1 de octubre para la ponencia en Madrid.

Pilar López Navasa
Ejecutiva de cuentas SR
mobilePhone
682 872 042
emailAddress
pilarlopez@qmscomunicacion.com

Pilar López a través de antispam.mailspamprotection.com
23 jul, 11:53
para hola@jonhernandez.education, Jon, Pablo, Iban, Rosa

Te compartimos los datos de facturación:
QMS COMUNICACIÓN
C/ Colombia 64 7A 28016 Madrid
CIF: B- 83567529
''');

    expect(values['company'], 'QMS COMUNICACIÓN');
    expect(values['contact'], 'Pilar López Navasa');
    expect(values['email'], 'pilarlopez@qmscomunicacion.com');
    expect(values['phone'], '682 872 042');
    expect(values['date'], '2026-10-01');
    expect(values['population'], 'Madrid');
    expect(values['amount'], '6000');
    expect(values['tax_company'], 'QMS COMUNICACIÓN');
    expect(values['tax_id'], 'B-83567529');
    expect(values['tax_address'], 'C/ Colombia 64 7A');
    expect(values['tax_postal'], '28016');
    expect(values['tax_population'], 'Madrid');
  });

  test(
    'encuentra fiscalidad y contacto aunque Gmail no etiquete el bloque',
    () {
      final values = extractCommunicationFicha('''
Eva Alejandre a través de antispam.mailspamprotection.com
eva@butragueno-bottlander.com
Eva Alejandre
Supervisora de Cuentas
c/ Lazaga, 12, 28020, Madrid
+34 914491224 620834629
Nos gustaría una ponencia el 9 de septiembre en Ávila.
Para poder bloquear la fecha, enviadnos los datos fiscales.
Mario Chavero
Te paso los datos de nuestra empresa, aunque ya nos habéis facturado anteriormente:
Butragueño & Bottländer SL
Calle Lazaga, 12
28020 de Madrid
B85550507
Jon confirma un fee de 6k más gastos.
''');

      expect(values['contact'], 'Eva Alejandre');
      expect(values['email'], 'eva@butragueno-bottlander.com');
      expect(values['phone'], '620 834 629');
      expect(values['company'], 'Butragueño & Bottländer SL');
      expect(values['tax_company'], 'Butragueño & Bottländer SL');
      expect(values['tax_id'], 'B85550507');
      expect(values['tax_address'], 'Calle Lazaga, 12');
      expect(values['tax_postal'], '28020');
      expect(values['tax_population'], 'Madrid');
      expect(values['amount'], '6000');
    },
  );

  test('no confunde el día de la ponencia con el importe', () {
    final values = extractCommunicationFicha('''
Jon confirma un fee de 6k más gastos.
El tema del fee queda pendiente de cerrar para el 9 de septiembre.
''');

    expect(values['amount'], '6000');
  });
}
