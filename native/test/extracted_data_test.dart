import 'package:bills_maker/utils/extracted_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('carga por separado la fecha de factura y la fecha del evento', () {
    final data = <String, dynamic>{
      'invoice_date': '19/07/2026',
      'ponencia_date': '2026-09-03',
    };

    expect(extractedInvoiceDate(data), '2026-07-19');
    expect(extractedEventDate(data), '2026-09-03');
  });

  test('acepta los alias devueltos por extractores anteriores', () {
    expect(extractedInvoiceDate({'fecha_factura': '7-8-2026'}), '2026-08-07');
    expect(extractedInvoiceDate({'document_date': ''}), isNull);
  });

  test('forma el concepto de ponencia con fecha y detalle', () {
    expect(
      extractedConcept(
        details: 'la IA, ¿ola o tsunami?',
        eventDate: '2026-09-03',
      ),
      'Ponencia del 03/09/2026. La IA, ¿ola o tsunami?',
    );
    expect(
      extractedConcept(details: '', eventDate: '2026-09-03'),
      'Ponencia del 03/09/2026. La IA, ¿ola o tsunami?',
    );
  });
}
