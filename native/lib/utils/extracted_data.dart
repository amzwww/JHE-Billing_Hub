import 'package:intl/intl.dart';

String? normalizeExtractedDate(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return DateFormat('yyyy-MM-dd').format(iso);
  for (final pattern in ['dd/MM/yyyy', 'd/M/yyyy', 'dd-MM-yyyy', 'd-M-yyyy']) {
    try {
      return DateFormat(
        'yyyy-MM-dd',
      ).format(DateFormat(pattern).parseStrict(raw));
    } catch (_) {}
  }
  return null;
}

String? extractedInvoiceDate(Map<String, dynamic> data) =>
    normalizeExtractedDate(
      data['invoice_date'] ?? data['fecha_factura'] ?? data['document_date'],
    );

String? extractedEventDate(Map<String, dynamic> data) =>
    normalizeExtractedDate(data['ponencia_date']);

const defaultPonenciaDetails = 'La IA, ¿ola o tsunami?';

String extractedConcept({
  required String details,
  String? eventDate,
  bool ponencia = true,
}) {
  final cleanDetails = details.trim();
  final title = cleanDetails.isEmpty && ponencia && eventDate != null
      ? defaultPonenciaDetails
      : cleanDetails.isEmpty
      ? ''
      : '${cleanDetails[0].toUpperCase()}${cleanDetails.substring(1)}';
  if (ponencia && eventDate != null) {
    final formattedDate = DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.parse(eventDate));
    // El concepto de ponencia tiene una redacción única y completa. Así se
    // mantiene también cuando la fecha llega de OCR con un texto parcial.
    return 'Ponencia del $formattedDate. $defaultPonenciaDetails';
  }
  if (title.isEmpty) return '';
  return eventDate == null
      ? title
      : '$title, ${DateFormat('dd/MM/yyyy').format(DateTime.parse(eventDate))}';
}
