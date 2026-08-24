import 'package:bills_maker/utils/modification_request_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepara gastos con decimal español', () {
    final suggestion = suggestedExpenseFromRequest(
      'Hay que añadir los gastos que son 393,99',
    );

    expect(suggestion?.description, 'Gastos');
    expect(suggestion?.amount, 393.99);
  });

  test('prepara gastos logísticos con punto decimal', () {
    final suggestion = suggestedExpenseFromRequest(
      'Añadir por favor los gastos logísticos que son: 293.99',
    );

    expect(suggestion?.description, 'Gastos de desplazamiento y logística');
    expect(suggestion?.amount, 293.99);
  });

  test('no modifica automáticamente una petición ambigua', () {
    expect(
      suggestedExpenseFromRequest('Revisar los gastos porque parecen altos'),
      isNull,
    );
  });
}
