import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bills_maker/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normaliza saltos ANSI sin dibujar caracteres de control', () {
    expect(
      normalizePdfText(
        'Primera línea\r\n\u001b[31mSegunda línea\u001b[0m\u000bTercera',
      ),
      'Primera línea\nSegunda líneaTercera',
    );
  });

  test(
    'genera una factura PDF nativa válida con impuestos y forma de pago',
    () async {
      final bytes = await buildDocumentPdf(
        {
          'invoice_number': 'JHE-2026-999',
          'invoice_date': '2026-07-18',
          'client_name': 'CLIENTE DE PRUEBA, S.L.',
          'client_tax_id': 'B12345678',
          'client_address_line1': 'Calle Ejemplo 1',
          'client_city_zip': '08018 Barcelona',
          'invoice_type': 'ponencia',
          'line_items': [
            {
              'description':
                  'Ponencia del 18/07/2026. La IA, ¿ola o tsunami? Sesión ejecutiva para analizar el impacto de la inteligencia artificial en la organización y su estrategia futura.\r\n\u001b[31mCon la presentación de resultados y próximos pasos\u001b[0m',
              'quantity': 1,
              'unit_price': 1000,
              'total': 1000,
            },
          ],
          'subtotal': 1000,
          'vat_rate': 21,
          'vat_label': 'IVA',
          'vat_amount': 210,
          'irpf_rate': 15,
          'irpf_amount': 150,
          'total': 1060,
          'pre_payment_note': '50% por adelantado',
          'post_payment_note': 'Texto posterior',
        },
        {
          'id': 'JHE',
          'name': 'Jonatan Hernández Vallvé',
          'tax_id': '46817238W',
          'address_line1': 'C/ Joan D’Austria 126',
          'city_zip': '08018 Barcelona',
          'phone': '0034 600 00 00 00',
          'ccc': '2100 0000 0000 0000 0000',
          'iban': 'ES00 2100 0000 0000 0000',
          'swift': 'CAIXESBBXXX',
        },
        isQuote: false,
      );
      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      if (Platform.environment['BILLS_PDF_QA'] == '1') {
        final directory = Directory('tmp/pdfs')..createSync(recursive: true);
        File(
          '${directory.path}/bills-maker-sample.pdf',
        ).writeAsBytesSync(bytes);
      }
    },
  );

  test('construye el nombre de archivo de factura con número y cliente', () {
    expect(
      documentPdfFileName({
        'invoice_number': 'JHE-2026-114',
        'client_name': 'EVENTOS PYMES SAS',
      }, isQuote: false),
      'JHE-2026-114 - EVENTOS PYMES SAS.pdf',
    );
    expect(
      documentPdfFileName({
        'invoice_number': 'JHE-2026-115',
        'client_name': 'ACME / Norte: S.L.',
      }, isQuote: false),
      'JHE-2026-115 - ACME Norte S.L.pdf',
    );
  });

  test('muestra la referencia rectificada tras el número de factura', () async {
    final bytes = await buildDocumentPdf(
      {
        'invoice_number': 'SKY-REC-2026-001',
        'invoice_date': '2026-07-29',
        'is_rectificative': true,
        'rectified_invoice_number': 'SKY-15-2025',
        'client_name': 'BIG IA DIGITAL, S.L.',
        'client_tax_id': 'B75977868',
        'client_address_line1': 'C/ Doctor Trueta 50, planta 3',
        'client_city_zip': '08005 Barcelona',
        'invoice_type': 'consultoria',
        'line_items': [
          {
            'description':
                'Remuneración por cargo de Administrador de la sociedad en el 2025',
            'quantity': 1,
            'unit_price': -450000,
            'total': -450000,
          },
        ],
        'subtotal': -450000,
        'vat_rate': 21,
        'vat_label': 'IVA',
        'vat_amount': -94500,
        'irpf_rate': 0,
        'irpf_amount': 0,
        'total': -544500,
        'post_payment_note': '',
      },
      {
        'id': 'SKY',
        'name': 'Skynet de Jon, S.L.',
        'tax_id': 'B19794072',
        'address_line1': "C/ Joan d'Àustria 126- 3-3",
        'city_zip': '08018 Barcelona',
        'ccc': '2100 0859 2102 0100 0843',
        'iban': 'ES75 2100 0859 2102 0100 0843',
        'swift': 'CAIXESBBXXX',
      },
      isQuote: false,
    );
    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    if (Platform.environment['BILLS_PDF_QA'] == '1') {
      final directory = Directory('tmp/pdfs')..createSync(recursive: true);
      File(
        '${directory.path}/bills-maker-rectificative-sample.pdf',
      ).writeAsBytesSync(bytes);
    }
  });
}
