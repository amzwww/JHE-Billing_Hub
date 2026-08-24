import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

Uint8List buildBillsExcel({
  required String sheetName,
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final workbook = Excel.createExcel();
  final defaultSheet = workbook.getDefaultSheet();
  final sheet = workbook[sheetName];
  if (defaultSheet != null && defaultSheet != sheetName)
    workbook.delete(defaultSheet);
  sheet.appendRow([for (final header in headers) TextCellValue(header)]);
  for (final row in rows) {
    sheet.appendRow([for (final value in row) TextCellValue(value)]);
  }
  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnWidth(column, 20);
  }
  final bytes = workbook.encode();
  if (bytes == null) throw StateError('No se ha podido crear el Excel.');
  return Uint8List.fromList(bytes);
}

Future<String?> saveBillsExcel({
  required String sheetName,
  required String filePrefix,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final bytes = buildBillsExcel(
    sheetName: sheetName,
    headers: headers,
    rows: rows,
  );
  final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  return FilePicker.platform.saveFile(
    dialogTitle: 'Exportar $sheetName',
    fileName: '$filePrefix-$date.xlsx',
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    bytes: bytes,
  );
}
