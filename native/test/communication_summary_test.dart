import 'package:bills_maker/utils/communication_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordena cronológicamente y redacta conclusiones', () {
    final result = summarizeCommunicationThread('''
12/02/2026 - Cliente: Solicita disponibilidad para una ponencia.
14/02/2026 - Andreu: Confirma fecha e importe.
10/02/2026 - Cliente: Primer contacto.
''');

    final first = result.indexOf('10/02/2026');
    final second = result.indexOf('12/02/2026');
    final third = result.indexOf('14/02/2026');
    expect(first, greaterThanOrEqualTo(0));
    expect(second, greaterThan(first));
    expect(third, greaterThan(second));
    expect(result, contains('CRONOLOGÍA RESUMIDA'));
    expect(result, contains('SITUACIÓN ACTUAL'));
  });

  test('entiende fechas habituales del encabezado de Gmail', () {
    final result = summarizeCommunicationThread('''
Cliente <cliente@example.com>
7 abr 2026, 10:32
para mí
Solicita una ponencia.
''');

    expect(result, contains('07/04/2026'));
    expect(result, contains('Cliente'));
  });

  test('resume hechos sin copiar fragmentos del correo original', () {
    const original =
        'Confirmarte que tenemos el OK al fee de 6.000€ más gastos de viaje. '
        'Así que vamos adelante para que puedas agendarte el día 1 de octubre.';
    final result = summarizeCommunicationThread('''
Pilar López <pilar@example.com>
13 jul 2026, 9:14
$original

Yeimi <hola@example.com>
16 jul 2026, 17:19
La factura de la ponencia se emite por adelantado.
Preferimos gestionar nosotros la logística y facturarla por separado.
Podemos comentarlo con nuestro equipo de marketing para valorar una publicación en LinkedIn.

Pilar López <pilar@example.com>
23 jul 2026, 11:53
Te compartimos los datos de facturación:
QMS COMUNICACIÓN
C/ Colombia 64 7A 28016 Madrid
CIF: B-83567529
''');

    expect(
      result,
      contains('Confirma la contratación por 6.000 € más los gastos de viaje.'),
    );
    expect(
      result,
      contains(
        'El equipo de Jon gestionará la logística y la facturará por separado.',
      ),
    );
    expect(
      result,
      contains(
        'Facilita los datos fiscales necesarios para emitir la factura.',
      ),
    );
    expect(result, isNot(contains(original)));
    expect(result, contains('Datos fiscales recibidos de QMS COMUNICACIÓN'));
  });
}
