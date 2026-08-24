import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import '../services/pdf_service.dart';
import '../utils/extracted_data.dart';
import '../utils/modification_request_parser.dart';

const _invoiceCurrencies = <String, String>{
  'EUR': 'Euros (€)',
  'USD': 'Dólares estadounidenses (USD)',
  'GBP': 'Libras esterlinas (GBP)',
};

class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage({
    super.key,
    required this.isQuote,
    this.existing,
    this.seedQuote,
    this.billingRequest,
    this.modificationRequest,
    this.initialIssuer = 'JHE',
    this.initialType = 'ponencia',
  });

  final bool isQuote;
  final Map<String, dynamic>? existing;
  final Map<String, dynamic>? seedQuote;
  final Map<String, dynamic>? billingRequest;
  final String? modificationRequest;
  final String initialIssuer;
  final String initialType;

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  final _service = BillsService();
  final _formKey = GlobalKey<FormState>();
  final _date = TextEditingController();
  final _eventDate = TextEditingController();
  final _expectedTotal = TextEditingController();
  final _clientName = TextEditingController();
  final _clientTaxId = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _cityZip = TextEditingController();
  final _country = TextEditingController();
  final _ourReference = TextEditingController();
  final _theirOrder = TextEditingController();
  final _parentInvoice = TextEditingController();
  final _irpfRate = TextEditingController();
  final _prePayment = TextEditingController();
  final _notes = TextEditingController();
  final _uniAccounting = TextEditingController();
  final _uniAccountingCode = TextEditingController();
  final _uniManaging = TextEditingController();
  final _uniManagingCode = TextEditingController();
  final _uniProcessing = TextEditingController();
  final _uniProcessingCode = TextEditingController();
  final _uniProposing = TextEditingController();
  final _uniProposingCode = TextEditingController();
  final List<_LineItemDraft> _items = [];

  List<Map<String, dynamic>> _issuers = [];
  String _issuerId = 'JHE';
  String _type = 'ponencia';
  String _currency = 'EUR';
  bool _foreign = false;
  bool _canary = false;
  bool _university = false;
  bool _address2Enabled = false;
  double _igicRate = 0;
  bool _saving = false;
  bool _extracting = false;
  bool _loading = true;
  List<int> _gaps = [];
  int? _nextSeq;
  int? _chosenSeq;
  String _prePaymentKey = 'none';
  String? _automaticModificationSummary;

  bool get _editing => widget.existing != null;
  String get _dateColumn => widget.isQuote ? 'quote_date' : 'invoice_date';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final issuers = await _service.issuers();
    final source = widget.existing ?? widget.seedQuote;
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _date.text = widget.seedQuote != null && widget.existing == null
        ? now
        : source?[_dateColumn]?.toString() ??
              source?['quote_date']?.toString() ??
              now;
    _issuerId = source?['issuer_id']?.toString() ?? widget.initialIssuer;
    _type = source?['invoice_type']?.toString() ?? widget.initialType;
    _currency = _normalizeCurrency(source?['currency']);
    _irpfRate.text =
        source?['irpf_rate']?.toString() ?? (_issuerId == 'JHE' ? '15' : '0');
    if (widget.seedQuote != null && _type == 'mixta') _type = 'ponencia';
    _clientName.text = _s(source?['client_name']);
    _clientTaxId.text = _s(source?['client_tax_id']);
    _address1.text = _s(source?['client_address_line1']);
    _address2.text = _s(source?['client_address_line2']);
    _address2Enabled = _address2.text.isNotEmpty;
    _cityZip.text = _s(source?['client_city_zip']);
    _country.text = _s(source?['client_country']);
    _ourReference.text = _s(source?['our_reference']);
    _theirOrder.text = _s(source?['their_order']);
    _parentInvoice.text = _s(source?['parent_invoice_number']);
    _prePayment.text = _s(source?['pre_payment_note']);
    _prePaymentKey = _prePaymentKeyFor(_prePayment.text);
    _notes.text = _s(source?['notes']);
    _foreign = source?['client_is_foreign'] == true;
    _canary = source?['client_is_canary'] == true;
    _university = source?['is_university'] == true;
    _igicRate = _n(source?['vat_rate']);
    _uniAccounting.text = _s(source?['university_accounting_office']);
    _uniAccountingCode.text = _s(source?['university_accounting_office_code']);
    _uniManaging.text = _s(source?['university_managing_body']);
    _uniManagingCode.text = _s(source?['university_managing_body_code']);
    _uniProcessing.text = _s(source?['university_processing_unit']);
    _uniProcessingCode.text = _s(source?['university_processing_unit_code']);
    _uniProposing.text = _s(source?['university_proposing_body']);
    _uniProposingCode.text = _s(source?['university_proposing_body_code']);

    final rows = source?['line_items'] as List?;
    if (rows == null || rows.isEmpty) {
      _items.add(_LineItemDraft(description: _defaultDescription(_type)));
    } else {
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        _items.add(_LineItemDraft.fromMap(row));
      }
    }
    _eventDate.text = _inferEventDate(_items);
    final request = widget.billingRequest;
    if (request != null && !_editing && widget.seedQuote == null) {
      final requestDate = DateTime.tryParse(_s(request['presentation_date']));
      final formattedEventDate = requestDate == null
          ? ''
          : DateFormat('dd/MM/yyyy').format(requestDate);
      _clientName.text = _s(request['tax_company_name']).isNotEmpty
          ? _s(request['tax_company_name'])
          : _s(request['company_name']);
      _clientTaxId.text = _s(request['tax_id']);
      _address1.text = _s(request['tax_address']);
      final postal = _s(request['tax_postal_code']);
      final population = _s(request['tax_population']);
      _cityZip.text = [
        postal,
        population,
      ].where((value) => value.isNotEmpty).join(' ');
      _eventDate.text = _s(request['presentation_date']);
      if (_items.isNotEmpty) {
        _items.first.description.text = formattedEventDate.isEmpty
            ? _defaultDescription(_type)
            : extractedConcept(
                details: '',
                eventDate: _s(request['presentation_date']),
                ponencia: _type == 'ponencia',
              );
        final amount = _n(request['presentation_amount']);
        if (amount > 0) {
          _items.first.quantity.text = '1';
          _items.first.unitPrice.text = _LineItemDraft._format(amount);
        }
      }
      final expenses = _n(request['logistics_expenses']);
      if (expenses > 0) {
        const label = 'Gastos de desplazamiento y logística';
        _items.add(
          _LineItemDraft(description: label, unitPrice: expenses)
            ..indented = true,
        );
      }
      final paymentForm = _s(request['payment_form']);
      _prePayment.text = _requestPaymentNote(paymentForm);
      _prePaymentKey = _prePaymentKeyFor(_prePayment.text);
    }
    if (_editing) _prepareModificationRequestDraft();
    if (!_editing) {
      if (widget.isQuote) {
        final year = DateTime.tryParse(_date.text)?.year ?? DateTime.now().year;
        _nextSeq = await _service.nextQuoteSequence(_issuerId, year);
      } else {
        await _refreshSequence();
      }
    }
    if (mounted)
      setState(() {
        _issuers = issuers;
        _loading = false;
      });
  }

  @override
  void dispose() {
    for (final controller in [
      _date,
      _eventDate,
      _expectedTotal,
      _clientName,
      _clientTaxId,
      _address1,
      _address2,
      _cityZip,
      _country,
      _ourReference,
      _theirOrder,
      _parentInvoice,
      _irpfRate,
      _prePayment,
      _notes,
      _uniAccounting,
      _uniAccountingCode,
      _uniManaging,
      _uniManagingCode,
      _uniProcessing,
      _uniProcessingCode,
      _uniProposing,
      _uniProposingCode,
    ]) {
      controller.dispose();
    }
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshSequence() async {
    final date = DateTime.tryParse(_date.text);
    if (date == null) return;
    final values = await Future.wait([
      _service.nextInvoiceSequence(_issuerId, date.year),
      _service.invoiceGaps(_issuerId, date.year),
    ]);
    _nextSeq = values[0] as int;
    _gaps = values[1] as List<int>;
    _chosenSeq = null;
  }

  String get _previewNumber {
    if (_editing)
      return _s(
        widget.existing?[widget.isQuote ? 'quote_number' : 'invoice_number'],
      );
    final date = DateTime.tryParse(_date.text);
    if (date == null) return '…';
    final seq = _chosenSeq ?? _nextSeq;
    if (seq == null) return '…';
    return widget.isQuote
        ? '$_issuerId-PF-${date.year}-${seq.toString().padLeft(3, '0')}'
        : '$_issuerId-${date.year}-${seq.toString().padLeft(3, '0')}';
  }

  double get _subtotal => _round2(
    _items.fold(0, (sum, item) => sum + (item.parentHeader ? 0 : item.total)),
  );

  ({
    double vatRate,
    String vatLabel,
    double vat,
    double irpfRate,
    double irpf,
    double total,
  })
  get _taxes {
    final subtotal = _subtotal;
    if (_foreign)
      return (
        vatRate: 0,
        vatLabel: 'IVA',
        vat: 0,
        irpfRate: 0,
        irpf: 0,
        total: subtotal,
      );
    final vatRate = _canary ? _igicRate : 21.0;
    final parsedIrpfRate =
        double.tryParse(_irpfRate.text.trim().replaceAll(',', '.')) ?? 0;
    final irpfRate = parsedIrpfRate.clamp(0, 100).toDouble();
    final vat = _round2(subtotal * vatRate / 100);
    final irpf = _round2(subtotal * irpfRate / 100);
    return (
      vatRate: vatRate,
      vatLabel: _canary ? 'IGIC' : 'IVA',
      vat: vat,
      irpfRate: irpfRate,
      irpf: irpf,
      total: _round2(subtotal + vat - irpf),
    );
  }

  Future<void> _save({bool downloadPdf = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final parsedDate = DateTime.tryParse(_date.text.trim());
    if (parsedDate == null)
      return _message('La fecha debe tener formato AAAA-MM-DD.');
    final existing = widget.existing;
    if (existing != null && !widget.isQuote) {
      final originalDate = DateTime.tryParse(_s(existing['invoice_date']));
      if (originalDate != null &&
          _date.text.trim() != _s(existing['invoice_date'])) {
        if (parsedDate.year != originalDate.year) {
          return _message(
            'La fecha debe mantenerse dentro del año de la factura original.',
          );
        }
        final today = DateTime.now();
        final todayOnly = DateTime(today.year, today.month, today.day);
        if (parsedDate.isBefore(todayOnly)) {
          final number = _s(existing['invoice_number']);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirmar cambio de fecha'),
              content: Text(
                'La fecha ${DateFormat('dd/MM/yyyy').format(parsedDate)} es anterior a hoy. '
                '¿Confirmas que quieres modificar la fecha de la factura $number?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }
      }
    }
    if (_items.where((item) => item.description.text.trim().isNotEmpty).isEmpty)
      return _message('Añade al menos un concepto.');
    if (!widget.isQuote &&
        _type == 'complemento' &&
        _parentInvoice.text.trim().isEmpty) {
      return _message('Falta el número de la factura principal.');
    }
    setState(() => _saving = true);
    try {
      final year = parsedDate.year;
      int seq;
      String number;
      if (existing != null) {
        seq = (existing['seq'] as num).toInt();
        number = _s(
          existing[widget.isQuote ? 'quote_number' : 'invoice_number'],
        );
      } else if (widget.isQuote) {
        seq = await _service.nextQuoteSequence(_issuerId, year);
        number = '$_issuerId-PF-$year-${seq.toString().padLeft(3, '0')}';
      } else {
        if (_chosenSeq != null &&
            await _service.invoiceSequenceExists(
              _issuerId,
              year,
              _chosenSeq!,
            )) {
          throw Exception(
            'El hueco ${_chosenSeq!} ya se ha reutilizado. Actualiza la pantalla.',
          );
        }
        seq = _chosenSeq ?? await _service.nextInvoiceSequence(_issuerId, year);
        number = '$_issuerId-$year-${seq.toString().padLeft(3, '0')}';
      }
      final taxes = _taxes;
      final computedType = _type == 'ponencia'
          ? _classifyInvoice(_items)
          : _type;
      final payload = <String, dynamic>{
        widget.isQuote ? 'quote_number' : 'invoice_number': number,
        _dateColumn: _date.text.trim(),
        'year': year,
        'seq': seq,
        'issuer_id': _issuerId,
        'invoice_type': computedType,
        'currency': _currency,
        'client_name': _clientName.text.trim(),
        'client_tax_id': _nullIfEmpty(_clientTaxId.text),
        'client_address_line1': _nullIfEmpty(_address1.text),
        'client_address_line2': _address2Enabled
            ? _nullIfEmpty(_address2.text)
            : null,
        'client_city_zip': _nullIfEmpty(_cityZip.text),
        'client_country': _nullIfEmpty(_country.text),
        'client_is_foreign': _foreign,
        'client_is_canary': _canary,
        'is_university': _university,
        'our_reference': _nullIfEmpty(_ourReference.text),
        'their_order': _nullIfEmpty(_theirOrder.text),
        if (!widget.isQuote)
          'parent_invoice_number': _nullIfEmpty(_parentInvoice.text),
        'line_items': [for (final item in _items) item.toMap()],
        'subtotal': _subtotal,
        'vat_rate': taxes.vatRate,
        'vat_label': taxes.vatLabel,
        'vat_amount': taxes.vat,
        'irpf_rate': taxes.irpfRate,
        'irpf_amount': taxes.irpf,
        'total': taxes.total,
        'pre_payment_note': _nullIfEmpty(_prePayment.text),
        if (!widget.isQuote)
          'post_payment_note': computedType == 'sponsor'
              ? null
              : _postPaymentNote,
        'notes': _nullIfEmpty(_notes.text),
        if (widget.billingRequest != null)
          'billing_request_id': _s(widget.billingRequest?['id']),
        'status': widget.isQuote
            ? (existing?['status'] ?? 'draft')
            : (existing?['status'] ?? 'issued'),
        if (!widget.isQuote && widget.seedQuote != null)
          'source_quote_number': _nullIfEmpty(
            _s(widget.seedQuote?['quote_number']),
          ),
        'university_accounting_office': _university
            ? _nullIfEmpty(_uniAccounting.text)
            : null,
        'university_accounting_office_code': _university
            ? _nullIfEmpty(_uniAccountingCode.text)
            : null,
        'university_managing_body': _university
            ? _nullIfEmpty(_uniManaging.text)
            : null,
        'university_managing_body_code': _university
            ? _nullIfEmpty(_uniManagingCode.text)
            : null,
        'university_processing_unit': _university
            ? _nullIfEmpty(_uniProcessing.text)
            : null,
        'university_processing_unit_code': _university
            ? _nullIfEmpty(_uniProcessingCode.text)
            : null,
        'university_proposing_body': _university
            ? _nullIfEmpty(_uniProposing.text)
            : null,
        if (widget.isQuote)
          'university_proposing_body': _university
              ? _nullIfEmpty(_uniProposing.text)
              : null,
      };
      if (widget.isQuote) {
        await _service.saveQuote(payload, id: existing?['id']?.toString());
      } else {
        await _service.saveInvoice(payload, id: existing?['id']?.toString());
        final seedId = widget.seedQuote?['id']?.toString();
        if (seedId != null) await _service.convertQuote(seedId, number);
      }
      if (downloadPdf) {
        final issuer = _issuers.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id'] == _issuerId,
          orElse: () => null,
        );
        if (issuer != null)
          await saveDocumentPdf(payload, issuer, isQuote: widget.isQuote);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _message('No se pudo guardar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _extractClient() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (picked == null) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) return _message('No se pudo leer el archivo.');
    setState(() => _extracting = true);
    try {
      final extension = (file.extension ?? '').toLowerCase();
      final mime = switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final data = await _service.extractClient(
        Uint8List.fromList(bytes),
        mime,
      );
      _clientName.text = _s(data['client_name']);
      _clientTaxId.text = _s(data['client_tax_id']);
      _address1.text = _s(data['client_address_line1']);
      _address2.text = _s(data['client_address_line2']);
      _address2Enabled = _address2.text.isNotEmpty;
      _cityZip.text = _s(data['client_city_zip']);
      _country.text = _s(data['client_country']);
      if (data['is_foreign'] is bool) _foreign = data['is_foreign'] as bool;
      if (data['is_canary'] is bool) _canary = data['is_canary'] as bool;
      if (_foreign) _canary = false;
      if (_canary) _foreign = false;

      final invoiceDate = extractedInvoiceDate(data);
      if (invoiceDate != null && !_editing) {
        _date.text = invoiceDate;
        await _refreshSequence();
      }
      final eventDate = extractedEventDate(data);
      if (eventDate != null) {
        _eventDate.text = eventDate;
      }
      if (_type == 'complemento' &&
          _s(data['parent_invoice_number']).trim().isNotEmpty) {
        _parentInvoice.text = _s(data['parent_invoice_number']).trim();
      }

      final details = _s(data['details']).trim();
      if ((details.isNotEmpty || eventDate != null) && _items.isNotEmpty) {
        final description = extractedConcept(
          details: details,
          eventDate: eventDate,
          ponencia: _type == 'ponencia',
        );
        _items.first.description.text = description;
      }
      final amount = _n(data['amount']);
      if (amount > 0 && _items.isNotEmpty) {
        _items.first.quantity.text = '1';
        _items.first.unitPrice.text = _LineItemDraft._format(amount);
      }
      final expenses = _n(data['expenses']);
      if (expenses > 0 && _type != 'complemento') {
        const label = 'Gastos de desplazamiento y logística';
        final existing = _items.indexWhere(
          (item) => item.description.text == label,
        );
        final item = _LineItemDraft(description: label, unitPrice: expenses)
          ..indented = true;
        if (existing >= 0) {
          _items[existing].dispose();
          _items[existing] = item;
        } else {
          _items.add(item);
        }
      }
      if (mounted) {
        setState(() {});
        _message('Datos extraídos de ${file.name}.');
      }
    } catch (error) {
      if (mounted) _message('No se pudieron extraer los datos: $error');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _loadPreviousClient() async {
    try {
      final rows = await _service.invoices();
      final unique = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final key =
            '${row['issuer_id']}::${_s(row['client_name']).toLowerCase()}';
        unique.putIfAbsent(key, () => row);
      }
      if (!mounted) return;
      final selected = await showSearch<Map<String, dynamic>?>(
        context: context,
        delegate: _PreviousClientDelegate(unique.values.toList()),
      );
      if (selected == null) return;
      _clientName.text = _s(selected['client_name']);
      _clientTaxId.text = _s(selected['client_tax_id']);
      _address1.text = _s(selected['client_address_line1']);
      _address2.text = _s(selected['client_address_line2']);
      _address2Enabled = _address2.text.isNotEmpty;
      _cityZip.text = _s(selected['client_city_zip']);
      _country.text = _s(selected['client_country']);
      _foreign = selected['client_is_foreign'] == true;
      _canary = selected['client_is_canary'] == true;
      setState(() {});
    } catch (error) {
      if (mounted) _message('No se pudieron cargar los clientes: $error');
    }
  }

  void _updateEventDescription() {
    final parsed = DateTime.tryParse(_eventDate.text);
    final description = parsed == null
        ? ''
        : extractedConcept(
            details: '',
            eventDate: DateFormat('yyyy-MM-dd').format(parsed),
            ponencia: _type == 'ponencia',
          );
    if (_type == 'ponencia' && _items.isNotEmpty && description.isNotEmpty) {
      _items.first.description.text = description;
    } else if (_type == 'complemento') {
      while (_items.length < 2) _items.add(_LineItemDraft());
      _items.first
        ..description.text = description
        ..quantity.text = '0'
        ..unitPrice.text = '0'
        ..parentHeader = true;
      _items[1]
        ..description.text = _complementLine
        ..indented = true;
    }
    setState(() {});
  }

  void _reconcileTotal() {
    final expected = _n(_expectedTotal.text);
    if (expected <= 0) return;
    final diff = _round2(expected - _taxes.total);
    if (diff == 0) return _message('El total ya coincide.');
    if (diff.abs() > 1)
      return _message(
        'Solo se concilian diferencias de redondeo de hasta 1 €.',
      );
    final multiplier = 1 + _taxes.vatRate / 100 - _taxes.irpfRate / 100;
    final targetSubtotal = _round2(expected / multiplier);
    final adjustable = _items.lastWhere((item) => !item.parentHeader);
    final newTotal = _round2(adjustable.total + targetSubtotal - _subtotal);
    final quantity = _n(adjustable.quantity.text) == 0
        ? 1
        : _n(adjustable.quantity.text);
    adjustable.unitPrice.text = _LineItemDraft._format(
      _round2(newTotal / quantity),
    );
    setState(() {});
    _message('Última línea ajustada para conciliar el redondeo.');
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _prepareModificationRequestDraft() {
    final suggestion = suggestedExpenseFromRequest(widget.modificationRequest);
    if (suggestion == null) return;
    final alreadyPresent = _items.any(
      (item) =>
          item.description.text.toLowerCase().contains('gasto') &&
          (item.total - suggestion.amount).abs() < 0.01,
    );
    if (!alreadyPresent) {
      _items.add(
        _LineItemDraft(
          description: suggestion.description,
          unitPrice: suggestion.amount,
        )..indented = true,
      );
    }
    _automaticModificationSummary = alreadyPresent
        ? 'La línea solicitada ya estaba incluida.'
        : 'Preparado automáticamente: ${suggestion.description} · ${suggestion.amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Widget _modificationRequestBanner(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 24, 10, compact ? 10 : 24, 0),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 170),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFF59E0B)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.edit_note, color: Color(0xFFB45309)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Modificación solicitada',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(widget.modificationRequest!.trim()),
                    if (_automaticModificationSummary != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _automaticModificationSummary!,
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final compact = MediaQuery.sizeOf(context).width < 700;
    final taxes = _taxes;
    final money = _moneyForCurrency(_currency);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compact ? 82 : 110,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_editing ? 'Editar' : 'Nueva'} ${widget.isQuote ? 'presupuesto' : 'factura'} · ${_typeLabel(_type)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 18 : 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${_editing ? 'Número' : 'Próximo número'}: $_previewNumber',
              style: TextStyle(
                fontSize: compact ? 12 : 15,
                fontWeight: FontWeight.normal,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              if (widget.modificationRequest?.trim().isNotEmpty == true)
                _modificationRequestBanner(compact),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.all(compact ? 10 : 24),
                    children: [
                      if (!_editing && !widget.isQuote && _gaps.isNotEmpty) ...[
                        _sequenceCard(),
                        const SizedBox(height: 28),
                      ],
                      _section(
                        'Datos de la factura',
                        Icons.receipt_long_outlined,
                        [
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _field(
                                _date,
                                'Fecha de factura (AAAA-MM-DD)',
                                width: 290,
                                required: true,
                                onChanged: (_) async {
                                  await _refreshSequence();
                                  if (mounted) setState(() {});
                                },
                              ),
                              _field(
                                _ourReference,
                                'Nuestra referencia (opcional)',
                                width: 290,
                              ),
                              _field(
                                _theirOrder,
                                'Según su pedido (opcional)',
                                width: 290,
                              ),
                              SizedBox(
                                width: 290,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _currency,
                                  decoration: const InputDecoration(
                                    labelText: 'Moneda',
                                  ),
                                  items: [
                                    for (final entry
                                        in _invoiceCurrencies.entries)
                                      DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                  ],
                                  onChanged: (value) => setState(
                                    () => _currency = _normalizeCurrency(value),
                                  ),
                                ),
                              ),
                              if (_type == 'ponencia' ||
                                  _type == 'complemento' ||
                                  _type == 'formacion')
                                _field(
                                  _eventDate,
                                  'Fecha de la ponencia (AAAA-MM-DD)',
                                  width: 890,
                                  onChanged: (_) => _updateEventDescription(),
                                ),
                            ],
                          ),
                          if (_type == 'ponencia')
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Generará: Ponencia del DD/MM/AAAA. La IA, ¿ola o tsunami?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _section('Cliente', Icons.business, [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _loadPreviousClient,
                              icon: const Icon(Icons.search),
                              label: const Text('Cargar cliente anterior'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _extracting ? null : _extractClient,
                              icon: _extracting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.document_scanner_outlined),
                              label: Text(
                                _extracting
                                    ? 'Extrayendo datos…'
                                    : 'Subir captura del cliente',
                              ),
                            ),
                            const Text(
                              'o selecciona un PDF o imagen',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            _field(
                              _clientName,
                              'Nombre / razón social',
                              width: 440,
                              required: true,
                            ),
                            _field(_clientTaxId, 'NIF / CIF', width: 240),
                            _field(_address1, 'Dirección', width: 440),
                            SizedBox(
                              width: 890,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text('Dirección 2 (opcional)'),
                                    value: _address2Enabled,
                                    onChanged: (value) => setState(
                                      () => _address2Enabled = value ?? false,
                                    ),
                                  ),
                                  TextField(
                                    controller: _address2,
                                    enabled: _address2Enabled,
                                  ),
                                ],
                              ),
                            ),
                            _field(_cityZip, 'CP y ciudad', width: 300),
                            _field(_country, 'País', width: 240),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('Cliente extranjero'),
                              selected: _foreign,
                              onSelected: (value) => setState(() {
                                _foreign = value;
                                if (value) _canary = false;
                              }),
                            ),
                            FilterChip(
                              label: const Text('Canarias'),
                              selected: _canary,
                              onSelected: (value) => setState(() {
                                _canary = value;
                                if (value) _foreign = false;
                              }),
                            ),
                            FilterChip(
                              label: const Text('Universidad'),
                              selected: _university,
                              onSelected: (value) =>
                                  setState(() => _university = value),
                            ),
                            if (_canary)
                              SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<double>(
                                  initialValue: _igicRate,
                                  decoration: const InputDecoration(
                                    labelText: 'IGIC',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 0,
                                      child: Text('0 %'),
                                    ),
                                    DropdownMenuItem(
                                      value: 7,
                                      child: Text('7 %'),
                                    ),
                                    DropdownMenuItem(
                                      value: 20,
                                      child: Text('20 %'),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _igicRate = value ?? 0),
                                ),
                              ),
                            SizedBox(
                              width: 180,
                              child: TextField(
                                controller: _irpfRate,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'IRPF (%)',
                                  helperText: 'Jon: 15 · Bright/Skynet: 0',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ]),
                      if (_university) ...[
                        const SizedBox(height: 18),
                        _section(
                          'Códigos DIR3 de universidad',
                          Icons.account_balance,
                          [
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                _field(
                                  _uniAccounting,
                                  'Oficina contable',
                                  width: 280,
                                ),
                                _field(
                                  _uniAccountingCode,
                                  'Código',
                                  width: 180,
                                ),
                                _field(
                                  _uniManaging,
                                  'Órgano gestor',
                                  width: 280,
                                ),
                                _field(_uniManagingCode, 'Código', width: 180),
                                _field(
                                  _uniProcessing,
                                  'Unidad tramitadora',
                                  width: 280,
                                ),
                                _field(
                                  _uniProcessingCode,
                                  'Código',
                                  width: 180,
                                ),
                                _field(
                                  _uniProposing,
                                  'Órgano proponente',
                                  width: 280,
                                ),
                                _field(_uniProposingCode, 'Código', width: 180),
                              ],
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (_type == 'complemento')
                        _section('Factura principal', Icons.tag, [
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _field(
                                _parentInvoice,
                                'Número de factura principal',
                                width: 890,
                              ),
                            ],
                          ),
                        ]),
                      const SizedBox(height: 18),
                      _section('Conceptos', Icons.list_alt, [
                        for (var i = 0; i < _items.length; i++) _lineEditor(i),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _items.add(_LineItemDraft())),
                            icon: const Icon(Icons.add),
                            label: const Text('Añadir línea'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      _section(
                        'Texto antes de la forma de pago',
                        Icons.payments_outlined,
                        [
                          DropdownButtonFormField<String>(
                            initialValue: _prePaymentKey,
                            items: [
                              for (final entry in _prePaymentOptions.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value.label),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              _prePaymentKey = value ?? 'none';
                              if (_prePaymentKey != 'other')
                                _prePayment.text =
                                    _prePaymentOptions[_prePaymentKey]!.text;
                            }),
                          ),
                          if (_prePaymentKey == 'other') ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _prePayment,
                              minLines: 3,
                              maxLines: 6,
                              decoration: const InputDecoration(
                                hintText: 'Texto libre',
                              ),
                            ),
                          ],
                          if (_prePaymentKey != 'none' &&
                              _prePaymentKey != 'other') ...[
                            const SizedBox(height: 12),
                            Text(
                              _prePayment.text,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                          if (_type != 'sponsor') ...[
                            const SizedBox(height: 20),
                            const Text(
                              'Bajo la forma de pago siempre aparecerá:',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              _postPaymentNote,
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                      _section('Notas', Icons.notes, [
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Notas internas / adicionales',
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: 360,
                              child: Column(
                                children: [
                                  _amount('Subtotal', _subtotal, money),
                                  _amount(
                                    '${taxes.vatLabel} ${taxes.vatRate.toStringAsFixed(0)} %',
                                    taxes.vat,
                                    money,
                                  ),
                                  _amount(
                                    'IRPF ${_percent(taxes.irpfRate)} %',
                                    -taxes.irpf,
                                    money,
                                  ),
                                  const Divider(),
                                  _amount(
                                    'TOTAL',
                                    taxes.total,
                                    money,
                                    bold: true,
                                  ),
                                  const SizedBox(height: 18),
                                  TextField(
                                    controller: _expectedTotal,
                                    decoration: const InputDecoration(
                                      labelText: 'Total esperado (opcional)',
                                      hintText: 'Ej: 1210.00',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton(
                                      onPressed: _reconcileTotal,
                                      child: const Text('Conciliar redondeo'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 14,
                          children: [
                            OutlinedButton(
                              onPressed: _saving ? null : () => _save(),
                              child: const Text('Guardar'),
                            ),
                            FilledButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _save(downloadPdf: true),
                              icon: const Icon(Icons.file_download_outlined),
                              label: Text(
                                _saving
                                    ? 'Guardando…'
                                    : 'Guardar y descargar PDF',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineEditor(int index) {
    final item = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = TextField(
            controller: item.description,
            decoration: const InputDecoration(labelText: 'Descripción'),
            onChanged: (_) => setState(() {}),
          );
          final quantity = TextField(
            controller: item.quantity,
            enabled: !item.parentHeader,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cantidad'),
            onChanged: (_) => setState(() {}),
          );
          final price = TextField(
            controller: item.unitPrice,
            enabled: !item.parentHeader,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Precio'),
            onChanged: (_) => setState(() {}),
          );
          final actions = <Widget>[
            IconButton(
              tooltip: 'Sangría',
              onPressed: () => setState(() => item.indented = !item.indented),
              icon: Icon(
                Icons.format_indent_increase,
                color: item.indented
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            IconButton(
              tooltip: 'Solo encabezado (sin importes)',
              onPressed: () => setState(() {
                item.parentHeader = !item.parentHeader;
                if (item.parentHeader) {
                  item.quantity.text = '0';
                  item.unitPrice.text = '0';
                }
              }),
              icon: Icon(
                Icons.title,
                color: item.parentHeader
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: _items.length == 1
                  ? null
                  : () => setState(() {
                      item.dispose();
                      _items.removeAt(index);
                    }),
              icon: const Icon(Icons.delete_outline),
            ),
          ];
          if (constraints.maxWidth < 620) {
            return Column(
              children: [
                description,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: quantity),
                    const SizedBox(width: 10),
                    Expanded(child: price),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: description),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: quantity),
              const SizedBox(width: 10),
              SizedBox(width: 130, child: price),
              const SizedBox(width: 8),
              ...actions,
            ],
          );
        },
      ),
    );
  }

  Widget _sequenceCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF2F8),
      border: Border.all(color: const Color(0xFF8DA0C6)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final message = Text(
          'Huecos en la numeración: ${_gaps.length} número${_gaps.length == 1 ? '' : 's'} eliminado${_gaps.length == 1 ? '' : 's'}. ¿Quieres reutilizar uno en lugar del $_previewNumber?',
          style: const TextStyle(fontSize: 16),
        );
        final dropdown = DropdownButtonFormField<String>(
          initialValue: _chosenSeq == null ? 'next' : 'gap:$_chosenSeq',
          items: [
            DropdownMenuItem(
              value: 'next',
              child: Text('Siguiente (${_nextSeq ?? '…'})'),
            ),
            for (final gap in _gaps)
              DropdownMenuItem(
                value: 'gap:$gap',
                child: Text('Reutilizar ${gap.toString().padLeft(3, '0')}'),
              ),
          ],
          onChanged: (value) => setState(
            () => _chosenSeq = value == null || value == 'next'
                ? null
                : int.parse(value.substring(4)),
          ),
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [message, const SizedBox(height: 14), dropdown],
          );
        }
        return Row(
          children: [
            Expanded(child: message),
            const SizedBox(width: 18),
            SizedBox(width: 270, child: dropdown),
          ],
        );
      },
    ),
  );

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    double width = 260,
    bool required = false,
    ValueChanged<String>? onChanged,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = screenWidth < 700 ? screenWidth - 70 : width;
    final effectiveWidth = width > available ? available : width;
    return SizedBox(
      width: effectiveWidth,
      child: TextFormField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) =>
                  value == null || value.trim().isEmpty ? 'Obligatorio' : null
            : null,
      ),
    );
  }

  Widget _amount(
    String label,
    double value,
    NumberFormat money, {
    bool bold = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: bold ? 17 : 14,
          ),
        ),
        Text(
          money.format(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            fontSize: bold ? 17 : 14,
          ),
        ),
      ],
    ),
  );
}

class _LineItemDraft {
  _LineItemDraft({
    String description = '',
    double quantity = 1,
    double unitPrice = 0,
  }) : description = TextEditingController(text: description),
       quantity = TextEditingController(text: _format(quantity)),
       unitPrice = TextEditingController(text: _format(unitPrice));

  factory _LineItemDraft.fromMap(Map<String, dynamic> map) {
    final draft = _LineItemDraft(
      description: _s(map['description']),
      quantity: _n(map['quantity']),
      unitPrice: _n(map['unit_price']),
    );
    draft.indented = map['indented'] == true;
    draft.parentHeader = map['parent_header'] == true;
    return draft;
  }

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  bool indented = false;
  bool parentHeader = false;
  double get total => _round2(_n(quantity.text) * _n(unitPrice.text));
  Map<String, dynamic> toMap() => {
    'description': description.text.trim(),
    'quantity': _n(quantity.text),
    'unit_price': _n(unitPrice.text),
    'total': total,
    if (indented) 'indented': true,
    if (parentHeader) 'parent_header': true,
  };
  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }

  static String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

class _PreviousClientDelegate extends SearchDelegate<Map<String, dynamic>?> {
  _PreviousClientDelegate(this.clients);
  final List<Map<String, dynamic>> clients;

  @override
  String get searchFieldLabel => 'Buscar cliente anterior';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  Widget _results() {
    final filtered = clients
        .where(
          (row) =>
              '${row['client_name']} ${row['client_tax_id']} ${row['issuer_id']}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = filtered[index];
        return ListTile(
          leading: CircleAvatar(child: Text(_s(row['issuer_id']))),
          title: Text(
            _s(row['client_name']),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${_s(row['client_tax_id'])} · ${_s(row['client_city_zip'])}',
          ),
          onTap: () => close(context, row),
        );
      },
    );
  }
}

String _inferEventDate(List<_LineItemDraft> items) {
  final pattern = RegExp(r'(\d{2})/(\d{2})/(\d{4})');
  for (final item in items) {
    final match = pattern.firstMatch(item.description.text);
    if (match != null)
      return '${match.group(3)}-${match.group(2)}-${match.group(1)}';
  }
  return '';
}

String _classifyInvoice(List<_LineItemDraft> items) {
  var ponencia = false;
  var gastos = false;
  for (final item in items.where(
    (item) => !item.parentHeader && item.total != 0,
  )) {
    final description = item.description.text.trim().toLowerCase();
    final isExpense =
        description.startsWith('gastos') ||
        description.startsWith('costes') ||
        description.startsWith('coste ') ||
        description.startsWith('desplaza');
    if (isExpense) gastos = true;
    if (description.contains('ponencia') && !isExpense) ponencia = true;
  }
  if (ponencia && gastos) return 'mixta';
  if (ponencia) return 'ponencia';
  if (gastos) return 'gastos';
  return 'sponsor';
}

String _typeLabel(String type) =>
    const {
      'ponencia': 'Ponencia',
      'mixta': 'Mixta',
      'complemento': 'Complemento',
      'sponsor': 'Sponsor',
      'formacion': 'Formación',
      'master': 'Máster',
      'coworking': 'Coworking',
      'gastos': 'Gastos',
    }[type] ??
    type;

String _normalizeCurrency(dynamic value) {
  final code = value?.toString().trim().toUpperCase();
  return _invoiceCurrencies.containsKey(code) ? code! : 'EUR';
}

NumberFormat _moneyForCurrency(String code) {
  final normalized = _normalizeCurrency(code);
  final symbol = normalized == 'EUR' ? '€' : '$normalized ';
  return NumberFormat.currency(
    locale: 'es_ES',
    name: normalized,
    symbol: symbol,
  );
}

String _percent(double value) {
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _prePaymentKeyFor(String text) {
  for (final entry in _prePaymentOptions.entries) {
    if (entry.key != 'other' && entry.value.text == text) return entry.key;
  }
  return text.trim().isEmpty ? 'none' : 'other';
}

String _s(dynamic value) => value?.toString() ?? '';
double _n(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse('$value'.replaceAll(',', '.')) ?? 0;
double _round2(double value) => (value * 100).round() / 100;
String? _nullIfEmpty(String value) =>
    value.trim().isEmpty ? null : value.trim();
String _defaultDescription(String type) => switch (type) {
  'ponencia' => 'Ponencia. La IA, ¿ola o tsunami?',
  'complemento' =>
    'Gastos de desplazamiento y logística para la asistencia de Jon al evento',
  'formacion' => 'Servicios de formación',
  'master' => 'Máster',
  'coworking' => 'Coworking',
  _ => '',
};

String _requestPaymentNote(String value) => switch (value) {
  '100_before' => 'Se factura el 100% antes de la ponencia.',
  '50_initial' => 'Se factura el 50% inicial antes de la ponencia.',
  '50_remaining_expenses' =>
    'Se factura el restante 50% más los gastos de desplazamiento y logística.',
  _ => '',
};

const _complementLine =
    'Gastos de desplazamiento y logística para la asistencia de Jon al evento';

const _prePaymentOptions = <String, ({String label, String text})>{
  'none': (label: 'Ninguno', text: ''),
  'opt1': (
    label: '1 - 50% por adelantado',
    text:
        'Por autorización expresa, se factura el 50% de importe de la ponencia.\n\nQueda pendiente de facturar el 50% restante y los gastos de desplazamiento y logística de Jon para asistir al evento.',
  ),
  'opt2': (
    label: '2 - Pendientes logística (y alojamiento)',
    text:
        'Quedan pendientes de facturar los costes de la logística de Jon para acudir al evento y, si fuera preciso, alojamiento',
  ),
  'opt3': (
    label: '3 - Restante 50% + logística',
    text:
        'Se factura el restante 50% más los gastos de desplazamiento y logística de Jon para acudir al evento.',
  ),
  'other': (label: 'Otros (texto libre)', text: ''),
};

const _postPaymentNote =
    'Dado que la agenda de Jon se organiza con mucha antelación nos es preciso que la factura esté debidamente gestionada y cerrada con al menos un mes de antelación sobre la fecha de la ponencia\n\nAs Jon\'s agenda is planned well in advance, it is necessary for the invoice to be properly processed and finalized at least one month before the date of the keynote.';
