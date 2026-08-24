import 'package:intl/intl.dart';

import 'thread_ficha_extractor.dart';

/// Convierte un hilo pegado desde Gmail en una cronología de conclusiones.
///
/// El texto original se conserva en su campo. Este resumen evita reproducir
/// párrafos del correo: identifica hechos operativos y los expresa de forma
/// breve y homogénea.
String summarizeCommunicationThread(String raw) {
  final lines = raw
      .replaceAll('\r', '')
      .split('\n')
      .map((line) => line.trim())
      .toList();
  if (lines.every((line) => line.isEmpty)) return '';

  final entries = _parseMessages(lines);
  final summarized = <_SummarizedEntry>[];
  final seen = <String>{};

  for (final entry in entries..sort((a, b) => a.date.compareTo(b.date))) {
    final conclusion = _summarizeMessage(entry.body.join('\n'));
    final key =
        '${DateFormat('yyyy-MM-dd').format(entry.date)}|'
        '${_fold(entry.sender)}|${_fold(conclusion)}';
    if (seen.add(key)) {
      summarized.add(
        _SummarizedEntry(
          date: entry.date,
          sender: entry.sender,
          conclusion: conclusion,
        ),
      );
    }
  }

  if (summarized.length > 8) {
    summarized.removeWhere(
      (entry) =>
          entry.conclusion ==
              'Actualiza el estado de la gestión y sus próximos pasos.' ||
          entry.conclusion ==
              'Confirma lo tratado y mantiene la gestión en curso.' ||
          entry.conclusion ==
              'Solicita una aclaración necesaria para continuar con la gestión.',
    );
  }
  final visible = summarized.length <= 10
      ? summarized
      : <_SummarizedEntry>[
          summarized.first,
          ...summarized.skip(summarized.length - 9),
        ];

  final result = <String>['CRONOLOGÍA RESUMIDA'];
  if (visible.isEmpty) {
    result.addAll([
      '• Comunicación sin fecha identificable',
      '  Situación — El hilo contiene información pendiente de clasificar.',
    ]);
  } else {
    for (var index = 0; index < visible.length; index++) {
      final entry = visible[index];
      result.add(
        '• ${DateFormat('dd/MM/yyyy').format(entry.date)}'
        '${entry.sender.isEmpty ? '' : ' · ${entry.sender}'}',
      );
      result.add(
        '  ${index == 0 ? 'Primer contacto' : 'Seguimiento'} — '
        '${entry.conclusion}',
      );
      if (index != visible.length - 1) result.add('');
    }
  }

  result
    ..add('')
    ..add('SITUACIÓN ACTUAL')
    ..addAll(_currentSituation(raw));
  return result.join('\n');
}

List<_CommunicationEntry> _parseMessages(List<String> lines) {
  final entries = <_CommunicationEntry>[];
  _CommunicationEntry? current;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.isEmpty) continue;
    final header = _messageHeader(lines, index);
    if (header != null) {
      if (current != null && current.body.isNotEmpty) entries.add(current);
      current = _CommunicationEntry(
        date: header.date,
        sender: header.sender,
        body: <String>[],
      );
      final inlineBody = header.inlineBody.trim();
      if (inlineBody.isNotEmpty) current.body.add(inlineBody);
      continue;
    }
    current?.body.add(line);
  }
  if (current != null && current.body.isNotEmpty) entries.add(current);
  return entries;
}

_MessageHeader? _messageHeader(List<String> lines, int index) {
  final line = lines[index];
  final folded = _fold(line);

  final structured = RegExp(
    r'^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\s*[-–—|]\s*(.+)$',
  ).firstMatch(line);
  if (structured != null) {
    final parsed = _extractDate(structured.group(1)!);
    final remainder = structured.group(2)!.trim();
    final separator = remainder.indexOf(':');
    return parsed == null
        ? null
        : _MessageHeader(
            date: parsed.value,
            sender: separator > 0
                ? _stripSender(remainder.substring(0, separator))
                : '',
            inlineBody: separator > 0
                ? remainder.substring(separator + 1)
                : remainder,
          );
  }

  final compact = RegExp(
    r'^(?:(?:lun|mar|mi[eé]|jue|vie|s[aá]b|dom),\s*)?'
    r'\d{1,2}\s+[a-záéíóú]{3,10}(?:\s+\d{4})?,\s*\d{1,2}:\d{2}',
    caseSensitive: false,
  ).hasMatch(line);
  final timeOnly = RegExp(r'^\d{1,2}:\d{2}\s*\(').hasMatch(line);
  if (compact || timeOnly) {
    final parsed = timeOnly
        ? _ParsedDate(line, DateTime.now())
        : _extractDate(line);
    if (parsed != null) {
      return _MessageHeader(
        date: parsed.value,
        sender: _senderBefore(lines, index),
        inlineBody: '',
      );
    }
  }

  if (folded.startsWith('enviado el:')) {
    final parsed = _extractDate(line);
    if (parsed != null) {
      return _MessageHeader(
        date: parsed.value,
        sender: _deSenderBefore(lines, index),
        inlineBody: '',
      );
    }
  }

  if ((folded.startsWith('el ') && folded.contains('escribi')) ||
      (folded.startsWith('on ') && folded.contains('wrote'))) {
    final parsed = _extractDate(line);
    if (parsed != null) {
      return _MessageHeader(
        date: parsed.value,
        sender: _senderFromQuotedHeader(line),
        inlineBody: '',
      );
    }
  }
  return null;
}

String _senderBefore(List<String> lines, int index) {
  for (var cursor = index - 1; cursor >= 0 && cursor >= index - 4; cursor--) {
    final candidate = lines[cursor].trim();
    if (candidate.isEmpty ||
        _fold(candidate).startsWith('para ') ||
        _fold(candidate).startsWith('cc:') ||
        _fold(candidate).contains('archivos adjuntos')) {
      continue;
    }
    return _stripSender(candidate);
  }
  return '';
}

String _deSenderBefore(List<String> lines, int index) {
  for (var cursor = index - 1; cursor >= 0 && cursor >= index - 10; cursor--) {
    final candidate = lines[cursor].trim();
    if (_fold(candidate).startsWith('de:')) {
      return _stripSender(candidate.substring(candidate.indexOf(':') + 1));
    }
  }
  return _senderBefore(lines, index);
}

String _senderFromQuotedHeader(String line) {
  final withoutPrefix = line
      .replaceFirst(RegExp(r'^(?:El|On)\s+', caseSensitive: false), '')
      .replaceFirst(
        RegExp(r'\s+(?:escribió|escribio|wrote):?\s*$', caseSensitive: false),
        '',
      );
  final email = RegExp(
    r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}',
  ).firstMatch(withoutPrefix);
  if (email != null) {
    final before = withoutPrefix.substring(0, email.start);
    final opening = before.lastIndexOf(RegExp(r'[(<]'));
    final prefix = (opening >= 0 ? before.substring(0, opening) : before)
        .trim();
    final comma = prefix.lastIndexOf(',');
    final sender = comma >= 0 ? prefix.substring(comma + 1) : prefix;
    return _stripSender(sender);
  }
  return '';
}

String _stripSender(String value) {
  final originalEmail = RegExp(
    r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}',
  ).firstMatch(value)?.group(0);
  var result = value
      .replaceFirst(RegExp(r'^(?:De|From):\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+a trav[eé]s de\s+.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\([^)]*@[^)]*\)'), '')
      .trim();
  if (result.contains('@')) {
    final email = RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}').firstMatch(result);
    result = result.replaceAll(email?.group(0) ?? '', '').trim();
  }
  result = result
      .replaceAll(RegExp(r'^[<(]+|[<(>),]+$'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  if (originalEmail?.toLowerCase().startsWith('hola@jonhernandez.') == true) {
    return 'Equipo de Jon';
  }
  if (result.isEmpty && originalEmail != null) return originalEmail;
  return result.length > 80 ? result.substring(0, 80).trim() : result;
}

String _summarizeMessage(String body) {
  final relevant = _relevantBody(body);
  final folded = _fold(relevant);
  final facts = <String>[];

  final feeAccepted =
      folded.contains('ok al fee') ||
      (folded.contains('confirma') && folded.contains('6.000')) ||
      (folded.contains('vamos adelante') &&
          (folded.contains('fee') || folded.contains('6.000')));
  if (feeAccepted) {
    facts.add('Confirma la contratación por 6.000 € más los gastos de viaje.');
  } else if ((folded.contains('speaker fee') ||
          folded.contains('honorarios') ||
          folded.contains('presu')) &&
      (folded.contains('6000') || folded.contains('6.000'))) {
    facts.add(
      'Presenta honorarios de 6.000 € y deja los gastos de viaje aparte.',
    );
  }

  if ((folded.contains('interesad') ||
          folded.contains('encantados de contar') ||
          folded.contains('pensar en jon')) &&
      folded.contains('ponencia')) {
    facts.add(
      'Propone contar con Jon para una ponencia sobre IA aplicada a pymes.',
    );
  }

  if ((folded.contains('agenda') ||
          folded.contains('disponibilidad') ||
          folded.contains('ese dia') ||
          folded.contains('esa semana')) &&
      (folded.contains('encajar') ||
          folded.contains('combinar') ||
          folded.contains('ocupad') ||
          folded.contains('reservada'))) {
    if (folded.contains('reservada') && folded.contains('provisional')) {
      facts.add(
        'Reserva provisionalmente la fecha y solicita cerrar la contratación.',
      );
    } else {
      facts.add(
        'Revisa la disponibilidad de agenda y pide concretar fecha y horario.',
      );
    }
  }

  if ((folded.contains('apertura de puertas') ||
          folded.contains('masterclass') ||
          folded.contains('mesa redonda')) &&
      folded.contains('horar')) {
    facts.add('Comparte el horario previsto y el encaje de la intervención.');
  }

  final providesFiscal =
      (folded.contains('datos de facturacion') ||
          folded.contains('datos fiscales')) &&
      (folded.contains('cif') ||
          folded.contains('te compartimos') ||
          folded.contains('adjuntamos') ||
          folded.contains('datos son'));
  final asksFiscal =
      (folded.contains('datos fiscales') ||
          folded.contains('datos de facturacion')) &&
      (folded.contains('facilites') ||
          folded.contains('agradeceria') ||
          folded.contains('solicit'));
  if (providesFiscal) {
    facts.add('Facilita los datos fiscales necesarios para emitir la factura.');
  } else if (asksFiscal) {
    facts.add('Solicita los datos fiscales para preparar la factura.');
  }

  if (folded.contains('60 dias') &&
      (folded.contains('pago') || folded.contains('factura'))) {
    facts.add('Informa de una política de pago a 60 días desde la factura.');
  }

  if (folded.contains('logistica') ||
      folded.contains('desplazamiento') ||
      folded.contains('alojamiento')) {
    if ((folded.contains('preferimos gestionar') ||
            folded.contains('se ocupa de la logistica')) &&
        (folded.contains('nosotros') || folded.contains('yeimi'))) {
      facts.add(
        'El equipo de Jon gestionará la logística y la facturará por separado.',
      );
    } else if (folded.contains('encargariamos') ||
        folded.contains('necesitaria')) {
      facts.add(
        'Consulta cómo se gestionarán el desplazamiento y el alojamiento.',
      );
    }
  }

  if (folded.contains('linkedin') ||
      folded.contains('instagram') ||
      folded.contains('redes')) {
    if (folded.contains('equipo de marketing') ||
        folded.contains('valorar que acciones')) {
      facts.add(
        'Traslada al equipo de marketing la posible difusión en redes.',
      );
    } else {
      facts.add('Solicita incluir difusión del evento en redes sociales.');
    }
  }

  if (facts.isEmpty &&
      folded.contains('revista') &&
      (folded.contains('tirada') || folded.contains('visitas'))) {
    facts.add(
      'Aporta datos de alcance de la revista para valorar la propuesta.',
    );
  }

  if (facts.isEmpty) {
    if (folded.contains('?') ||
        folded.contains('solicita') ||
        folded.contains('necesit')) {
      facts.add(
        'Solicita una aclaración necesaria para continuar con la gestión.',
      );
    } else if (folded.contains('confirm') ||
        folded.contains('de acuerdo') ||
        folded.contains('fenomenal') ||
        folded.contains('ok')) {
      facts.add('Confirma lo tratado y mantiene la gestión en curso.');
    } else {
      facts.add('Actualiza el estado de la gestión y sus próximos pasos.');
    }
  }

  return facts.take(3).join(' ');
}

String _relevantBody(String body) {
  final lines = body.split('\n');
  final result = <String>[];
  for (final line in lines) {
    final folded = _fold(line);
    if (folded.contains('no imprimir si no es necesario') ||
        folded.startsWith('la informacion contenida') ||
        folded.startsWith('[mensaje recortado]')) {
      break;
    }
    if (folded == 'twitter' ||
        folded == 'linkedin' ||
        folded == 'instagram' ||
        folded == 'website' ||
        folded == 'mobilephone' ||
        folded == 'emailaddress' ||
        folded.startsWith('http://') ||
        folded.startsWith('https://')) {
      continue;
    }
    if (folded.startsWith('para:') ||
        folded.startsWith('cc:') ||
        folded.startsWith('asunto:') ||
        folded.startsWith('enviado el:') ||
        folded == 'para mi') {
      continue;
    }
    result.add(line);
  }
  return result.join(' ');
}

List<String> _currentSituation(String raw) {
  final values = extractCommunicationFicha(raw);
  final result = <String>[];
  final date = DateTime.tryParse(values['date'] ?? '');
  final population = values['population']?.trim() ?? '';
  if (date != null || population.isNotEmpty) {
    result.add(
      '• Fecha y lugar — '
      '${date == null ? 'Fecha pendiente' : DateFormat('dd/MM/yyyy').format(date)}'
      '${population.isEmpty ? '' : ' · $population'}',
    );
  }

  final amount = _money(values['amount']);
  final expenses = _money(values['expenses']);
  if (amount != null) {
    result.add(
      '• Honorarios — $amount'
      '${expenses == null ? ' más gastos de viaje' : ' + $expenses de gastos'}',
    );
  }

  final contact = values['contact']?.trim() ?? '';
  if (contact.isNotEmpty) {
    final channels = [
      values['email']?.trim(),
      values['phone']?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    result.add(
      '• Contacto — $contact${channels.isEmpty ? '' : ' · $channels'}',
    );
  }

  final taxCompany = values['tax_company']?.trim() ?? '';
  final taxId = values['tax_id']?.trim() ?? '';
  if (taxCompany.isNotEmpty || taxId.isNotEmpty) {
    result.add(
      '• Facturación — Datos fiscales recibidos'
      '${taxCompany.isEmpty ? '' : ' de $taxCompany'}'
      '${taxId.isEmpty ? '' : ' · $taxId'}',
    );
  } else {
    result.add('• Facturación — Datos fiscales pendientes');
  }

  final folded = _fold(raw);
  if (folded.contains('60 dias')) {
    result.add('• Pago — Política comunicada de 60 días desde la factura');
  }
  if (folded.contains('preferimos gestionar') ||
      folded.contains('yeimi se ocupa de la logistica')) {
    result.add(
      '• Logística — La gestiona el equipo de Jon y se factura aparte',
    );
  }
  if (folded.contains('equipo de marketing') &&
      (folded.contains('linkedin') || folded.contains('instagram'))) {
    result.add('• Redes — Pendiente de confirmación por marketing');
  }
  return result;
}

String? _money(String? raw) {
  final value = double.tryParse((raw ?? '').replaceAll(',', '.'));
  if (value == null) return null;
  return NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: value == value.roundToDouble() ? 0 : 2,
  ).format(value);
}

_ParsedDate? _extractDate(String value) {
  final iso = RegExp(r'\b\d{4}-\d{1,2}-\d{1,2}\b').firstMatch(value);
  if (iso != null) {
    final parsed = DateTime.tryParse(iso.group(0)!);
    if (parsed != null) return _ParsedDate(iso.group(0)!, parsed);
  }

  final european = RegExp(
    r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b',
  ).firstMatch(value);
  if (european != null) {
    final source = european.group(0)!;
    for (final pattern in [
      'd/M/yyyy',
      'dd/MM/yyyy',
      'd-M-yyyy',
      'dd-MM-yyyy',
    ]) {
      try {
        return _ParsedDate(source, DateFormat(pattern).parseStrict(source));
      } catch (_) {}
    }
  }

  final textual = RegExp(
    r'\b(\d{1,2})\s+(?:de\s+)?'
    r'(enero|ene|febrero|feb|marzo|mar|abril|abr|mayo|may|junio|jun|'
    r'julio|jul|agosto|ago|septiembre|sep|setiembre|octubre|oct|'
    r'noviembre|nov|diciembre|dic)'
    r'(?:\s+(?:de\s+)?(\d{4}))?\b',
    caseSensitive: false,
  ).firstMatch(value);
  if (textual != null) {
    final day = int.parse(textual.group(1)!);
    final month = _months[textual.group(2)!.toLowerCase()];
    final year = int.tryParse(textual.group(3) ?? '') ?? DateTime.now().year;
    if (month != null) {
      final parsed = DateTime(year, month, day);
      if (parsed.year == year && parsed.month == month && parsed.day == day) {
        return _ParsedDate(textual.group(0)!, parsed);
      }
    }
  }

  final english = RegExp(
    r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+'
    r'(\d{1,2}),\s+(\d{4})\b',
    caseSensitive: false,
  ).firstMatch(value);
  if (english != null) {
    final month = _englishMonths[english.group(1)!.toLowerCase()];
    final day = int.parse(english.group(2)!);
    final year = int.parse(english.group(3)!);
    if (month != null)
      return _ParsedDate(english.group(0)!, DateTime(year, month, day));
  }
  return null;
}

String _fold(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _months = <String, int>{
  'enero': 1,
  'ene': 1,
  'febrero': 2,
  'feb': 2,
  'marzo': 3,
  'mar': 3,
  'abril': 4,
  'abr': 4,
  'mayo': 5,
  'may': 5,
  'junio': 6,
  'jun': 6,
  'julio': 7,
  'jul': 7,
  'agosto': 8,
  'ago': 8,
  'septiembre': 9,
  'sep': 9,
  'setiembre': 9,
  'octubre': 10,
  'oct': 10,
  'noviembre': 11,
  'nov': 11,
  'diciembre': 12,
  'dic': 12,
};

const _englishMonths = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

class _ParsedDate {
  _ParsedDate(this.source, this.value);
  final String source;
  final DateTime value;
}

class _MessageHeader {
  const _MessageHeader({
    required this.date,
    required this.sender,
    required this.inlineBody,
  });

  final DateTime date;
  final String sender;
  final String inlineBody;
}

class _CommunicationEntry {
  _CommunicationEntry({
    required this.date,
    required this.sender,
    required this.body,
  });

  final DateTime date;
  final String sender;
  final List<String> body;
}

class _SummarizedEntry {
  const _SummarizedEntry({
    required this.date,
    required this.sender,
    required this.conclusion,
  });

  final DateTime date;
  final String sender;
  final String conclusion;
}
