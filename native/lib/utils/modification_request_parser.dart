class SuggestedExpenseLine {
  const SuggestedExpenseLine({required this.description, required this.amount});

  final String description;
  final double amount;
}

SuggestedExpenseLine? suggestedExpenseFromRequest(String? request) {
  final text = request?.trim() ?? '';
  if (text.isEmpty) return null;
  final wantsToAdd = RegExp(
    r'\b(añad\w*|agreg\w*|inclu\w*|sum\w*|incorpor\w*)\b',
    caseSensitive: false,
  ).hasMatch(text);
  if (!wantsToAdd || !text.toLowerCase().contains('gasto')) return null;

  final match = RegExp(
    r'gastos?[^0-9]{0,80}((?:\d{1,3}(?:[.\s]\d{3})+|\d+)(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  final amount = _parseLocalizedAmount(match?.group(1));
  if (amount == null || amount <= 0) return null;

  final lower = text.toLowerCase();
  final description = lower.contains('viaje')
      ? 'Gastos de viaje'
      : lower.contains('logíst') || lower.contains('logistic')
      ? 'Gastos de desplazamiento y logística'
      : 'Gastos';
  return SuggestedExpenseLine(description: description, amount: amount);
}

double? _parseLocalizedAmount(String? raw) {
  var value = raw?.replaceAll(' ', '') ?? '';
  if (value.isEmpty) return null;
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  } else if (value.contains('.')) {
    final parts = value.split('.');
    if (parts.length > 2) {
      final decimal = parts.last.length == 2 ? '.${parts.last}' : '';
      final integerParts = decimal.isEmpty
          ? parts
          : parts.sublist(0, parts.length - 1);
      value = '${integerParts.join()}$decimal';
    } else if (parts.last.length == 3) {
      value = parts.join();
    }
  }
  return double.tryParse(value);
}
