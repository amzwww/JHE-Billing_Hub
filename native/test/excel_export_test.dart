import 'package:bills_maker/services/excel_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('genera un XLSX válido con los datos exportados', () {
    final bytes = buildBillsExcel(
      sheetName: 'Facturas',
      headers: const ['Número', 'Cliente', 'Total'],
      rows: const [
        ['JHE-2026-001', 'Cliente prueba', '1060.00'],
      ],
    );
    expect(bytes.length, greaterThan(1000));
    expect(bytes.take(2), [0x50, 0x4B]);
  });
}
