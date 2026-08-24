import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String _text(dynamic value) => value?.toString() ?? '';

/// Normaliza texto procedente de correos y pegados de otras aplicaciones.
/// Algunos clientes guardan los saltos como CR/ANSI y el motor PDF puede
/// dibujarlos como pequeños cuadrados dentro de la factura.
String normalizePdfText(dynamic value) {
  var text = _text(value)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u2028', '\n')
      .replaceAll('\u2029', '\n');
  text = text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');

  final clean = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x0A) {
      clean.write('\n');
    } else if (rune == 0x09) {
      clean.write(' ');
    } else if (rune >= 0x20 && rune != 0x7F) {
      clean.writeCharCode(rune);
    }
  }
  return clean.toString();
}

String _percent(dynamic value) {
  final text = _number(value).toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _currencyCode(dynamic value) {
  final code = value?.toString().trim().toUpperCase();
  return const {'EUR', 'USD', 'GBP'}.contains(code) ? code! : 'EUR';
}

String _money(dynamic value, dynamic currency) {
  final amount = _number(value);
  final code = _currencyCode(currency);
  final number = NumberFormat('#,##0.00', 'es_ES').format(amount);
  return '$number ${code == 'EUR' ? '€' : code}';
}

({String ccc, String iban, String swift}) _paymentDetails(
  Map<String, dynamic> document,
  Map<String, dynamic> issuer,
) {
  // Jon utiliza una cuenta bancaria distinta cuando la factura se cobra en
  // dólares. El resto de emisores y monedas conservan sus datos configurados.
  final isJonUsd =
      _text(issuer['id']).toUpperCase() == 'JHE' &&
      _currencyCode(document['currency']) == 'USD';
  if (isJonUsd) {
    return (
      ccc: '0049 0094 4128 1007 5514',
      iban: 'ES92 0049 0094 4128 1007 5514',
      swift: 'BSCHESMMXXX',
    );
  }
  return (
    ccc: _text(issuer['ccc']),
    iban: _text(issuer['iban']),
    swift: _text(issuer['swift']),
  );
}

Future<Uint8List> buildDocumentPdf(
  Map<String, dynamic> document,
  Map<String, dynamic> issuer, {
  required bool isQuote,
}) async {
  final pdf = pw.Document();
  final regularData = await rootBundle.load('assets/fonts/Lato-Regular.ttf');
  final boldData = await rootBundle.load('assets/fonts/Lato-Bold.ttf');
  final regularFont = pw.Font.ttf(regularData);
  final boldFont = pw.Font.ttf(boldData);
  final number = _text(document[isQuote ? 'quote_number' : 'invoice_number']);
  final date = _text(document[isQuote ? 'quote_date' : 'invoice_date']);
  final items = (document['line_items'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final postPaymentText = _text(document['post_payment_note']).isNotEmpty
      ? _text(document['post_payment_note'])
      : (_text(document['invoice_type']) == 'sponsor'
            ? ''
            : _defaultPostPaymentNote);
  final navy = PdfColor.fromHex('#142A5C');
  final blue = PdfColor.fromHex('#1E40AF');
  final payment = _paymentDetails(document, issuer);

  pdf.addPage(
    pw.MultiPage(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
        italic: regularFont,
        boldItalic: boldFont,
      ),
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(38),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _text(issuer['name']),
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _text(issuer['tax_id']),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    _text(issuer['address_line1']),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (_text(issuer['address_line2']).isNotEmpty)
                    pw.Text(
                      _text(issuer['address_line2']),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  pw.Text(
                    _text(issuer['city_zip']),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (_text(issuer['phone']).isNotEmpty)
                    pw.Text(
                      'Teléfono ${_text(issuer['phone'])}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  document['is_rectificative'] == true
                      ? 'FACTURA\nRECTIFICATIVA'
                      : (isQuote ? 'PRESUPUESTO' : 'FACTURA'),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    color: document['is_rectificative'] == true
                        ? PdfColors.red700
                        : blue,
                    fontSize: document['is_rectificative'] == true ? 20 : 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 16),
                _pdfLabelValue('FECHA:', _formatDate(date)),
                _pdfInvoiceNumber(
                  isQuote ? 'PRESUPUESTO Nº:' : 'FACTURA Nº:',
                  number,
                  isRectificative: document['is_rectificative'] == true,
                  rectifiedInvoiceNumber: _text(
                    document['rectified_invoice_number'],
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 32),
        pw.Text(
          'FACTURAR A:',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _text(document['client_name']),
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        if (_text(document['client_tax_id']).isNotEmpty)
          pw.Text(
            _text(document['client_tax_id']),
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (_text(document['client_address_line1']).isNotEmpty)
          pw.Text(
            _text(document['client_address_line1']),
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (_text(document['client_address_line2']).isNotEmpty)
          pw.Text(
            _text(document['client_address_line2']),
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (_text(document['client_city_zip']).isNotEmpty)
          pw.Text(
            _text(document['client_city_zip']),
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (_text(document['client_country']).isNotEmpty)
          pw.Text(
            _text(document['client_country']),
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (document['is_university'] == true) ..._universityRows(document),
        if (_text(document['their_order']).isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _pdfLabelValue(
            'SEGÚN SU Nº DE PEDIDO:',
            _text(document['their_order']),
            alignRight: false,
          ),
        ],
        if (_text(document['our_reference']).isNotEmpty) ...[
          pw.SizedBox(height: 4),
          _pdfLabelValue(
            'NUESTRA REFERENCIA:',
            _text(document['our_reference']),
            alignRight: false,
          ),
        ],
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: const ['DESCRIPCIÓN', 'PRECIO/UD', 'CANT', 'TOTAL'],
          data: [
            for (final item in items)
              [
                '${item['indented'] == true ? '    ' : ''}${normalizePdfText(item['description'])}',
                item['parent_header'] == true
                    ? ''
                    : _money(item['unit_price'], document['currency']),
                item['parent_header'] == true
                    ? ''
                    : _number(item['quantity']).toStringAsFixed(
                        _number(item['quantity']) ==
                                _number(item['quantity']).roundToDouble()
                            ? 0
                            : 2,
                      ),
                item['parent_header'] == true
                    ? ''
                    : _money(item['total'], document['currency']),
              ],
          ],
          headerDecoration: pw.BoxDecoration(color: blue),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          // Anchos fijos equivalentes al diseño original. La descripción se
          // parte en varias líneas dentro de su celda y nunca ensancha la tabla.
          columnWidths: const {
            0: pw.FixedColumnWidth(286.5),
            1: pw.FixedColumnWidth(83.6),
            2: pw.FixedColumnWidth(65.6),
            3: pw.FixedColumnWidth(83.6),
          },
          cellAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 245,
            child: pw.Column(
              children: [
                _totalRow(
                  'Subtotal',
                  _number(document['subtotal']),
                  currency: document['currency'],
                ),
                _totalRow(
                  '${_text(document['vat_label']).isEmpty ? 'IVA' : _text(document['vat_label'])} ${_number(document['vat_rate']).toStringAsFixed(0)}%',
                  _number(document['vat_amount']),
                  currency: document['currency'],
                ),
                _totalRow(
                  'IRPF ${_percent(document['irpf_rate'])}%',
                  -_number(document['irpf_amount']),
                  currency: document['currency'],
                ),
                pw.Divider(color: navy),
                _totalRow(
                  isQuote ? 'TOTAL PRESUPUESTO' : 'TOTAL FACTURA',
                  _number(document['total']),
                  currency: document['currency'],
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        if (_text(document['pre_payment_note']).isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text(
            _text(document['pre_payment_note']),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
        if (_text(document['vat_label']) == 'IGIC' &&
            _number(document['vat_rate']) == 0) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            '*Exención de IGIC por Inversión Sujeto Pasivo en virtud art. 19.1 2º de la Ley 20/1991',
            style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic),
          ),
        ],
        if (_text(document['notes']).isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            _text(document['notes']),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
        pw.SizedBox(height: 20),
        pw.Text(
          'Forma de pago:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
        if (payment.ccc.isNotEmpty)
          _pdfLabelValue('CCC:', payment.ccc, alignRight: false),
        if (payment.iban.isNotEmpty)
          _pdfLabelValue('IBAN:', payment.iban, alignRight: false),
        if (payment.swift.isNotEmpty)
          _pdfLabelValue('SWIFT:', payment.swift, alignRight: false),
        if (postPaymentText.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            postPaymentText,
            style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ],
    ),
  );
  return pdf.save();
}

String _formatDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : DateFormat('dd/MM/yyyy').format(parsed);
}

pw.Widget _pdfLabelValue(
  String label,
  String value, {
  bool alignRight = true,
}) => pw.Row(
  mainAxisSize: pw.MainAxisSize.min,
  mainAxisAlignment: alignRight
      ? pw.MainAxisAlignment.end
      : pw.MainAxisAlignment.start,
  children: [
    pw.Text(
      label,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(width: 8),
    pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
  ],
);

pw.Widget _pdfInvoiceNumber(
  String label,
  String number, {
  required bool isRectificative,
  required String rectifiedInvoiceNumber,
}) {
  final normal = const pw.TextStyle(fontSize: 9);
  final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  return pw.RichText(
    textAlign: pw.TextAlign.right,
    text: pw.TextSpan(
      children: [
        pw.TextSpan(text: label, style: bold),
        pw.TextSpan(text: '  $number', style: normal),
        if (isRectificative && rectifiedInvoiceNumber.isNotEmpty) ...[
          pw.TextSpan(text: '    Rectifica la factura nº ', style: bold),
          pw.TextSpan(text: rectifiedInvoiceNumber, style: normal),
        ],
      ],
    ),
  );
}

List<pw.Widget> _universityRows(Map<String, dynamic> document) {
  final rows = <({String label, String value, String code})>[
    (
      label: 'Oficina contable:',
      value: _text(document['university_accounting_office']),
      code: _text(document['university_accounting_office_code']),
    ),
    (
      label: 'Órgano Gestor:',
      value: _text(document['university_managing_body']),
      code: _text(document['university_managing_body_code']),
    ),
    (
      label: 'Unidad Tramitadora:',
      value: _text(document['university_processing_unit']),
      code: _text(document['university_processing_unit_code']),
    ),
    (
      label: 'Órgano proponente:',
      value: _text(document['university_proposing_body']),
      code: '',
    ),
  ];
  return [
    pw.SizedBox(height: 6),
    for (final row in rows.where((row) => row.value.isNotEmpty))
      _pdfLabelValue(
        row.label,
        row.code.isEmpty ? row.value : '${row.value} / Código: ${row.code}',
        alignRight: false,
      ),
  ];
}

const _defaultPostPaymentNote =
    'Dado que la agenda de Jon se organiza con mucha antelación nos es preciso que la factura esté debidamente gestionada y cerrada con al menos un mes de antelación sobre la fecha de la ponencia\n\nAs Jon\'s agenda is planned well in advance, it is necessary for the invoice to be properly processed and finalized at least one month before the date of the keynote.';

pw.Widget _totalRow(
  String label,
  double value, {
  required dynamic currency,
  bool bold = false,
}) {
  final style = pw.TextStyle(
    fontSize: bold ? 12 : 10,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  final row = pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(_money(value, currency), style: style),
      ],
    ),
  );
  return bold
      ? pw.Container(
          color: PdfColor.fromHex('#E6EBF5'),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: row,
        )
      : row;
}

String documentPdfFileName(
  Map<String, dynamic> document, {
  required bool isQuote,
}) {
  final number = _safeFilePart(
    _text(document[isQuote ? 'quote_number' : 'invoice_number']),
  );
  final fallback = isQuote ? 'presupuesto' : 'factura';
  if (isQuote) return '${number.isEmpty ? fallback : number}.pdf';

  final client = _safeFilePart(_text(document['client_name']));
  final base = [
    number.isEmpty ? fallback : number,
    client,
  ].where((part) => part.isNotEmpty).join(' - ');
  return '$base.pdf';
}

String _safeFilePart(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.replaceFirst(RegExp(r'[. ]+$'), '');
}

Future<String?> saveDocumentPdf(
  Map<String, dynamic> document,
  Map<String, dynamic> issuer, {
  required bool isQuote,
}) async {
  final bytes = await buildDocumentPdf(document, issuer, isQuote: isQuote);
  return FilePicker.platform.saveFile(
    dialogTitle: isQuote ? 'Guardar presupuesto' : 'Guardar factura',
    fileName: documentPdfFileName(document, isQuote: isQuote),
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
}

Future<void> printDocumentPdf(
  Map<String, dynamic> document,
  Map<String, dynamic> issuer, {
  required bool isQuote,
}) async {
  final bytes = await buildDocumentPdf(document, issuer, isQuote: isQuote);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: _text(document[isQuote ? 'quote_number' : 'invoice_number']),
  );
}
