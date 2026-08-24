/// Extracts the operational fields of a billing request from a pasted
/// communication thread. Gmail exports are noisy, so explicit labelled blocks
/// take priority and signatures near the latest billing-data message are used
/// as a fallback.
Map<String, String?> extractCommunicationFicha(String raw) {
  final lines = raw
      .replaceAll('\r', '')
      .split('\n')
      .map(_plain)
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const {};

  final contactAnchor = _lastIndexWhere(
    lines,
    (line) => _fold(line).startsWith('persona de contacto'),
  );
  final fiscalAnchor = _lastIndexWhere(lines, (line) {
    final value = _fold(line);
    return value.contains('datos fiscales') ||
        value.contains('datos de facturacion') ||
        value.contains('datos de facturación');
  });

  final contactBlock = contactAnchor < 0
      ? const <String>[]
      : _window(
          lines,
          contactAnchor + 1,
          fiscalAnchor > contactAnchor ? fiscalAnchor : contactAnchor + 12,
        );
  final labelledFiscalBlock = fiscalAnchor < 0
      ? const <String>[]
      : _window(lines, fiscalAnchor + 1, fiscalAnchor + 12);
  // En los hilos de Gmail la petición de datos fiscales suele aparecer antes
  // de la respuesta real. Si la respuesta no lleva una etiqueta como
  // "DATOS FISCALES", buscamos la evidencia fiscal más fiable: el CIF/NIF y
  // las líneas inmediatamente cercanas. Esto cubre respuestas del tipo
  // "Te paso los datos de nuestra empresa".
  final fiscalBlock = _selectFiscalBlock(lines, labelledFiscalBlock);

  var contact = _labeled(lines, const [
    'Persona de contacto',
    'Persona',
    'Contacto',
    'Att',
  ]);
  var email = _email(contactBlock.join('\n'));
  var phone = _phone(contactBlock.join('\n'));

  if (contact == null && contactBlock.isNotEmpty) {
    contact = contactBlock.where(_looksLikePerson).firstOrNull;
  }

  // Si el hilo procede directamente de Gmail, la persona suele aparecer en
  // la firma junto a un teléfono, sin una etiqueta "Persona de contacto".
  // Usamos esa señal antes de intentar interpretar los datos fiscales.
  contact ??= _contactNearPhone(lines);

  final fiscalSender = fiscalAnchor < 0
      ? null
      : _senderBefore(lines, fiscalAnchor);
  if (contact == null && fiscalSender != null) {
    contact = _bestFullName(lines, fiscalSender) ?? fiscalSender;
  }

  if (contact != null && (email == null || phone == null)) {
    final signature = _signatureFor(lines, contact);
    email ??= _email(signature.join('\n'));
    phone ??= _phone(signature.join('\n'));
  }

  email ??= _labeled(lines, const [
    'Mail de contacto',
    'Email de contacto',
    'Email',
    'Correo',
  ]);
  email ??= _emailForContact(lines, contact);
  phone ??= _phone(
    _labeled(lines, const [
          'Teléfono de contacto',
          'Telefono de contacto',
          'Teléfono',
          'Telefono',
          'Móvil',
          'Movil',
        ]) ??
        '',
  );

  final taxId =
      _taxId(fiscalBlock.join('\n')) ??
      _taxId(_labeled(lines, const ['CIF', 'NIF']) ?? '');
  final addressLine =
      _joinAddressLines(fiscalBlock) ??
      _labeled(lines, const ['DIRECCIÓN', 'Direccion', 'Domicilio']);
  final address = _splitAddress(addressLine);
  final fiscalCompany =
      _bestFiscalCompany(fiscalBlock) ??
      _labeled(lines, const ['RAZÓN SOCIAL', 'Razon social']);

  final population =
      _labeled(lines, const [
        'Población de la ponencia',
        'Poblacion de la ponencia',
        'Población',
        'Poblacion',
        'Ciudad',
        'Localidad',
      ]) ??
      _eventPopulation(lines);
  final amountValue = _labeled(lines, const [
    'Importe de la ponencia',
    'Importe',
    'Honorarios',
    'Precio',
    'Speaker fee',
    'Fee',
  ]);
  final expensesValue = _labeled(lines, const [
    'Gastos de logística',
    'Gastos logística',
    'Gastos',
    'Logística',
  ]);

  final company =
      _labeled(lines, const [
        'Nombre empresa',
        'Empresa',
        'Cliente',
        'Razón social',
        'Razon social',
      ]) ??
      fiscalCompany;

  final taxPopulation =
      _labeled(lines, const ['POBLACIÓN FISCAL', 'Poblacion fiscal']) ??
      address.city;
  final taxProvince =
      _labeled(lines, const ['PROVINCIA', 'Provincia']) ?? taxPopulation;

  return {
    'company': company,
    'contact': contact,
    'email': email,
    'phone': phone,
    'date': _eventDate(lines),
    'population': population,
    'amount': _money(amountValue) ?? _contextualAmount(lines),
    'expenses': _money(expensesValue),
    'tax_company': fiscalCompany ?? company,
    'tax_id': taxId,
    'tax_address': address.street ?? addressLine,
    'tax_postal': address.postal,
    'tax_population': taxPopulation,
    'tax_province': taxProvince,
  };
}

List<String> _selectFiscalBlock(
  List<String> lines,
  List<String> labelledBlock,
) {
  if (_taxId(labelledBlock.join('\n')) != null) return labelledBlock;

  // Prefer the last tax identifier in the pasted thread: Gmail normally
  // places the most recent response before the quoted history.
  final taxIndex = _lastIndexWhere(lines, (line) => _taxId(line) != null);
  if (taxIndex < 0) return labelledBlock;

  final start = (taxIndex - 8).clamp(0, lines.length);
  final end = (taxIndex + 4).clamp(start, lines.length);
  return lines.sublist(start, end);
}

String? _joinAddressLines(List<String> block) {
  final addressLines = block.where(_looksLikeAddress).toList();
  if (addressLines.isEmpty) return null;
  // A very common Gmail layout splits the street and the postal/city line:
  // "Calle Lazaga, 12" / "28020 de Madrid".
  return addressLines.join(' ');
}

String? _bestFiscalCompany(List<String> block) {
  final candidates = block.where(_looksLikeFiscalCompany).toList();
  if (candidates.isEmpty) return null;
  candidates.sort(
    (a, b) => _fiscalCompanyScore(b).compareTo(_fiscalCompanyScore(a)),
  );
  return candidates.first;
}

String? _contactNearPhone(List<String> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    if (_phone(lines[i]) == null) continue;
    final start = (i - 8).clamp(0, lines.length);
    final end = (i + 3).clamp(start, lines.length);
    final candidates = lines
        .sublist(start, end)
        .where(_looksLikePerson)
        .toList();
    if (candidates.isNotEmpty) return candidates.last;
  }
  return null;
}

String? _emailForContact(List<String> lines, String? contact) {
  final emails = <String>[];
  for (final line in lines) {
    final match = RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}').firstMatch(line);
    if (match == null) continue;
    final email = match.group(0)!.toLowerCase();
    final folded = _fold(line);
    final tokens = contact == null
        ? const <String>[]
        : _fold(contact)
              .split(RegExp(r'\s+'))
              .where((token) => token.length > 2)
              .take(2)
              .toList();
    if (tokens.isNotEmpty && tokens.every(folded.contains)) return email;
    if (!email.endsWith('@jonhernandez.education')) emails.add(email);
  }
  return emails.firstOrNull;
}

bool _looksLikeFiscalCompany(String line) {
  if (line.length < 2 ||
      line.length > 100 ||
      line.contains('@') ||
      RegExp(r'\d').hasMatch(line) ||
      _looksLikeAddress(line) ||
      _taxId(line) != null ||
      _looksLikeQuestionOrSentence(line)) {
    return false;
  }
  final folded = _fold(line);
  if (line.endsWith(':') ||
      RegExp(
        r'^(te|os|les|por favor|para|de cara|aunque|estos|los)\b',
      ).hasMatch(folded) ||
      folded.contains('datos de ') ||
      folded.contains('datos fiscales') ||
      folded.contains('datos de facturacion')) {
    return false;
  }
  final words = line.split(RegExp(r'\s+'));
  if (words.length > 12) return false;
  final legalSuffix = RegExp(
    r'\b(s\.?\s*l\.?|s\.?\s*a\.?|sll|sc|coop|slne)\b',
    caseSensitive: false,
  ).hasMatch(line);
  final letters = line.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
  final uppercase = letters.replaceAll(RegExp(r'[a-záéíóúüñ]'), '');
  return legalSuffix ||
      (letters.length >= 3 && uppercase.length / letters.length > .55);
}

int _fiscalCompanyScore(String line) {
  var score = 0;
  if (RegExp(
    r'\b(s\.?\s*l\.?|s\.?\s*a\.?|sll|sc|coop|slne)\b',
    caseSensitive: false,
  ).hasMatch(line)) {
    score += 10;
  }
  if (line == line.toUpperCase()) score += 3;
  return score;
}

String _plain(String value) => value.replaceAll(RegExp(r'[*_`]+'), '').trim();

String _fold(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n');

String? _labeled(List<String> lines, List<String> labels) {
  for (var i = lines.length - 1; i >= 0; i--) {
    final original = lines[i];
    final folded = _fold(original);
    for (final label in labels) {
      final foldedLabel = _fold(label);
      if (!folded.startsWith(foldedLabel)) continue;
      if (folded.length > foldedLabel.length) {
        final boundary = folded[foldedLabel.length];
        if (!RegExp(r'[\s:—–-]').hasMatch(boundary)) continue;
      }
      var remainder = original.substring(label.length).trim();
      remainder = remainder.replaceFirst(RegExp(r'^\s*[:—–-]\s*'), '');
      if (remainder.isNotEmpty) return remainder;
      if (i + 1 < lines.length && !_isKnownLabel(lines[i + 1])) {
        return lines[i + 1];
      }
    }
  }
  return null;
}

bool _isKnownLabel(String line) {
  final value = _fold(line);
  return value.startsWith('persona de contacto') ||
      value.startsWith('datos fiscales') ||
      value.startsWith('datos de facturacion') ||
      value.startsWith('importe') ||
      value.startsWith('poblacion') ||
      value.startsWith('cif') ||
      value.startsWith('nif');
}

List<String> _window(List<String> lines, int start, int end) {
  final safeStart = start.clamp(0, lines.length);
  final safeEnd = end.clamp(safeStart, lines.length);
  return lines.sublist(safeStart, safeEnd);
}

int _lastIndexWhere(List<String> lines, bool Function(String) test) {
  for (var i = lines.length - 1; i >= 0; i--) {
    if (test(lines[i])) return i;
  }
  return -1;
}

String? _senderBefore(List<String> lines, int anchor) {
  for (var i = anchor - 1; i >= 0 && i >= anchor - 12; i--) {
    final match = RegExp(
      r'^(.{2,70}?)\s+(?:a través de|<[\w.+-]+@)',
      caseSensitive: false,
    ).firstMatch(lines[i]);
    final candidate = match?.group(1)?.trim();
    if (candidate != null && _looksLikePerson(candidate)) return candidate;
  }
  return null;
}

String? _bestFullName(List<String> lines, String shortName) {
  final tokens = _fold(
    shortName,
  ).split(RegExp(r'\s+')).where((token) => token.length > 1).take(2).toList();
  if (tokens.isEmpty) return null;
  final candidates = lines.where((line) {
    final folded = _fold(line);
    return _looksLikePerson(line) &&
        tokens.every((token) => folded.contains(token));
  }).toList();
  candidates.sort((a, b) => b.length.compareTo(a.length));
  return candidates.firstOrNull;
}

List<String> _signatureFor(List<String> lines, String contact) {
  final tokens = _fold(
    contact,
  ).split(RegExp(r'\s+')).where((token) => token.length > 1).take(2).toList();
  if (tokens.isEmpty) return const [];
  for (var i = lines.length - 1; i >= 0; i--) {
    final folded = _fold(lines[i]);
    if (_looksLikePerson(lines[i]) &&
        tokens.every((token) => folded.contains(token))) {
      return _window(lines, i, i + 14);
    }
  }
  return const [];
}

bool _looksLikePerson(String line) {
  if (line.length < 5 || line.length > 70) return false;
  if (line.contains('@') || RegExp(r'\d').hasMatch(line)) return false;
  final folded = _fold(line);
  if (folded.contains('persona de contacto') ||
      folded.contains('datos fiscales') ||
      folded.contains('supervisora') ||
      folded.contains('ejecutiva de cuentas') ||
      folded.contains('director de') ||
      folded.contains('responsable de') ||
      folded.contains('account manager') ||
      folded.contains('commercial') ||
      folded.startsWith('para ') ||
      folded.startsWith('de:') ||
      folded.startsWith('enviado') ||
      folded.startsWith('asunto') ||
      folded.contains('a traves de') ||
      folded.contains('comunicacion contenida')) {
    return false;
  }
  final words = line.split(RegExp(r'\s+'));
  return words.length >= 2 &&
      words.length <= 6 &&
      words.every(
        (word) => RegExp(r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ.'-]+$").hasMatch(word),
      );
}

String? _email(String value) => RegExp(
  r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}',
).firstMatch(value)?.group(0)?.toLowerCase();

String? _phone(String value) {
  final matches = RegExp(
    r'(?<!\d)(?:(?:\+|00)34[\s.-]*)?([6789](?:[\s.-]*\d){8})(?!\d)',
  ).allMatches(value).toList();
  if (matches.isEmpty) return null;
  final match = matches.firstWhere(
    (candidate) => RegExp(
      r'^[67]',
    ).hasMatch(candidate.group(1)!.replaceAll(RegExp(r'\D'), '')),
    orElse: () => matches.first,
  );
  final digits = match.group(1)!.replaceAll(RegExp(r'\D'), '');
  return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
}

String? _taxId(String value) {
  final match = RegExp(
    r'\b([A-Za-z]\s*[- ]?\s*\d{7,8}[A-Za-z0-9]?|\d{8}\s*[- ]?\s*[A-Za-z])\b',
  ).firstMatch(value);
  if (match == null) return null;
  return match.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

bool _looksLikeAddress(String line) {
  final folded = _fold(line);
  return RegExp(r'\b\d{5}\b').hasMatch(line) ||
      folded.startsWith('c/') ||
      folded.startsWith('calle ') ||
      folded.startsWith('av ') ||
      folded.startsWith('avda') ||
      folded.startsWith('avenida ') ||
      folded.startsWith('plaza ') ||
      folded.startsWith('paseo ');
}

bool _looksLikeQuestionOrSentence(String line) {
  final folded = _fold(line);
  return line.contains('?') ||
      line.contains('¿') ||
      line.length > 75 ||
      folded.startsWith('te compart') ||
      folded.startsWith('estos son') ||
      folded.startsWith('los datos');
}

_AddressParts _splitAddress(String? line) {
  if (line == null) return const _AddressParts();
  final match = RegExp(r'\b(\d{5})\b').firstMatch(line);
  if (match == null) return _AddressParts(street: line);
  final street = line
      .substring(0, match.start)
      .trim()
      .replaceFirst(RegExp(r'[,;]+$'), '');
  final city = line
      .substring(match.end)
      .trim()
      .replaceFirst(RegExp(r'^[,; -]+'), '')
      .split(RegExp(r'[,;]'))
      .first
      .trim()
      .replaceFirst(RegExp(r'^(?:de|del)\s+', caseSensitive: false), '');
  return _AddressParts(
    street: street.isEmpty ? null : street,
    postal: match.group(1),
    city: city.isEmpty ? null : city,
  );
}

String? _money(String? value) {
  if (value == null) return null;
  // Nunca conviertas el día de una fecha del correo en un importe. Gmail
  // suele dejar mensajes posteriores como "fee para el 9 de septiembre";
  // primero quitamos esas fechas y sólo después buscamos cantidades.
  final withoutDates = value.replaceAll(
    RegExp(
      r'\b\d{1,2}\s+(?:de\s+)?(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\s+de\s+\d{4})?\b|'
      r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b',
      caseSensitive: false,
    ),
    ' ',
  );
  final thousands = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:k|mil)\b',
    caseSensitive: false,
  ).firstMatch(withoutDates);
  if (thousands != null) {
    final parsed = double.tryParse(thousands.group(1)!.replaceAll(',', '.'));
    if (parsed != null) return (parsed * 1000).toStringAsFixed(0);
  }
  final match = RegExp(
    r'(\d{1,3}(?:[.\s]\d{3})+(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)',
  ).firstMatch(withoutDates);
  if (match == null) return null;
  var number = match.group(1)!.replaceAll(' ', '');
  if (RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(number)) {
    number = number.replaceAll('.', '');
  } else if (number.contains(',') && number.contains('.')) {
    number = number.replaceAll('.', '').replaceAll(',', '.');
  } else if (number.contains(',')) {
    number = number.replaceAll(',', '.');
  }
  return number;
}

String? _contextualAmount(List<String> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    final folded = _fold(lines[i]);
    if (folded.contains('fee') ||
        folded.contains('honorarios') ||
        folded.contains('importe')) {
      final value = _money(lines[i]);
      if (value != null) return value;
    }
  }
  return null;
}

String? _eventPopulation(List<String> lines) {
  // Gmail places the newest visible messages first and then appends quoted
  // history. Prefer the first event-location statement so an older quoted
  // edition cannot replace the current one.
  for (final line in lines) {
    final folded = _fold(line);
    if (!(folded.contains('evento') ||
        folded.contains('ponencia') ||
        folded.contains('edicion') ||
        folded.contains('se llevara a cabo'))) {
      continue;
    }
    final match = RegExp(
      r'\ben\s+([A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ.-]+(?:\s+[A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ.-]+){0,2})',
    ).firstMatch(line);
    if (match != null) {
      final candidate = match.group(1)?.replaceFirst(RegExp(r'[.,;:]+$'), '');
      final rejected = {
        'linkedin',
        'instagram',
        'facebook',
        'youtube',
        'internet',
      };
      if (candidate != null && !rejected.contains(_fold(candidate))) {
        return candidate;
      }
    }
  }
  return null;
}

String? _eventDate(List<String> lines) {
  final explicit = _labeled(lines, const [
    'Fecha ponencia',
    'Fecha de la ponencia',
    'Fecha del evento',
    'Día',
  ]);
  final candidates = <String>[
    ?explicit,
    for (final line in lines.reversed)
      if (_fold(line).contains('ponencia') ||
          _fold(line).contains('evento') ||
          _fold(line).contains('agenda') ||
          _fold(line).contains('fecha'))
        line,
  ];
  for (final value in candidates) {
    final numeric = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b',
    ).firstMatch(value);
    if (numeric != null) {
      final year = numeric.group(3)!.length == 2
          ? '20${numeric.group(3)}'
          : numeric.group(3)!;
      return '$year-${numeric.group(2)!.padLeft(2, '0')}-${numeric.group(1)!.padLeft(2, '0')}';
    }
    final textual = RegExp(
      r'\b(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\s+de\s+(\d{4}))?\b',
      caseSensitive: false,
    ).firstMatch(value);
    if (textual != null) {
      final month = _months[_fold(textual.group(2)!)];
      final year = textual.group(3) ?? DateTime.now().year.toString();
      return '$year-${month!.toString().padLeft(2, '0')}-${textual.group(1)!.padLeft(2, '0')}';
    }
  }
  return null;
}

const _months = {
  'enero': 1,
  'febrero': 2,
  'marzo': 3,
  'abril': 4,
  'mayo': 5,
  'junio': 6,
  'julio': 7,
  'agosto': 8,
  'septiembre': 9,
  'octubre': 10,
  'noviembre': 11,
  'diciembre': 12,
};

class _AddressParts {
  const _AddressParts({this.street, this.postal, this.city});
  final String? street;
  final String? postal;
  final String? city;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
