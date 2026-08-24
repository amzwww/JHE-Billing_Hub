import 'dart:typed_data';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../services/bills_service.dart';
import '../services/excel_export.dart';
import '../services/pdf_service.dart';
import 'document_editor_page.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({
    super.key,
    required this.isQuote,
    required this.isAdmin,
    this.onBack,
    this.onOpenClients,
    this.onOpenHistory,
    this.refreshToken = 0,
  });

  final bool isQuote;
  final bool isAdmin;
  final VoidCallback? onBack;
  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenHistory;
  final int refreshToken;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final _service = BillsService();
  final _numberSearch = TextEditingController();
  final _clientSearch = TextEditingController();
  final _conceptSearch = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  Map<String, Map<String, dynamic>> _issuers = {};
  bool _loading = true;
  String _issuer = 'all';
  String _payment = 'all';
  final Set<String> _types = {};
  String _dateBasis = 'invoice';
  String _overdueDays = '30';
  String _sortKey = 'date';
  bool _sortAscending = false;
  final Set<String> _selectedRows = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DocumentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _numberSearch.dispose();
    _clientSearch.dispose();
    _conceptSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.isQuote ? _service.quotes() : _service.invoices(),
        _service.issuers(),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0];
        final availableIds = _rows.map(_rowId).toSet();
        _selectedRows.removeWhere((id) => !availableIds.contains(id));
        _issuers = {
          for (final issuer in results[1]) issuer['id'].toString(): issuer,
        };
      });
    } catch (error) {
      if (mounted) _message('No se pudieron cargar los datos: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final numberQuery = _numberSearch.text.trim().toLowerCase();
    final clientQuery = _clientSearch.text.trim().toLowerCase();
    final conceptQuery = _conceptSearch.text.trim().toLowerCase();
    final rows = _rows.where((row) {
      final number = _s(
        row[widget.isQuote ? 'quote_number' : 'invoice_number'],
      );
      final concepts = (row['line_items'] as List? ?? const [])
          .map((item) => _s((item as Map)['description']))
          .join(' ');
      final type = row['is_rectificative'] == true
          ? 'rectificativa'
          : _s(row['invoice_type']);
      return (numberQuery.isEmpty ||
              number.toLowerCase().contains(numberQuery)) &&
          (clientQuery.isEmpty ||
              '${row['client_name']} ${row['client_tax_id']}'
                  .toLowerCase()
                  .contains(clientQuery)) &&
          (conceptQuery.isEmpty ||
              concepts.toLowerCase().contains(conceptQuery)) &&
          (_issuer == 'all' || row['issuer_id'] == _issuer) &&
          (_types.isEmpty || _types.contains(type)) &&
          (widget.isQuote ||
              _payment == 'all' ||
              (_payment == 'paid' ? row['paid'] == true : row['paid'] != true));
    }).toList();
    dynamic sortValue(Map<String, dynamic> row) => switch (_sortKey) {
      'number' => _s(row[widget.isQuote ? 'quote_number' : 'invoice_number']),
      'event' => _eventDate(row) ?? '',
      'client' => _s(row['client_name']).toLowerCase(),
      'total' => _n(row['total']),
      _ => _s(row[widget.isQuote ? 'quote_date' : 'invoice_date']),
    };
    rows.sort((left, right) {
      final leftValue = sortValue(left);
      final rightValue = sortValue(right);
      final comparison = leftValue is num && rightValue is num
          ? leftValue.compareTo(rightValue)
          : leftValue.toString().compareTo(rightValue.toString());
      return _sortAscending ? comparison : -comparison;
    });
    return rows;
  }

  void _setSort(String key, bool ascending) => setState(() {
    _sortKey = key;
    _sortAscending = ascending;
  });

  int get _sortColumnIndex => switch (_sortKey) {
    'number' => 0,
    'date' => 1,
    'event' => widget.isQuote ? 1 : 2,
    'client' => widget.isQuote ? 2 : 3,
    'total' => widget.isQuote ? 5 : 6,
    _ => 1,
  };

  String _rowId(Map<String, dynamic> row) {
    final id = _s(row['id']);
    if (id.isNotEmpty) return id;
    return _s(row[widget.isQuote ? 'quote_number' : 'invoice_number']);
  }

  void _selectRow(Map<String, dynamic> row, bool selected) => setState(() {
    final id = _rowId(row);
    if (selected) {
      _selectedRows.add(id);
    } else {
      _selectedRows.remove(id);
    }
  });

  Future<void> _edit({
    Map<String, dynamic>? row,
    Map<String, dynamic>? seedQuote,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentEditorPage(
          isQuote: widget.isQuote && seedQuote == null,
          existing: row,
          seedQuote: seedQuote,
          initialIssuer: _s(row?['issuer_id']).isEmpty
              ? 'JHE'
              : _s(row?['issuer_id']),
          initialType: _s(row?['invoice_type']).isEmpty
              ? 'ponencia'
              : _s(row?['invoice_type']),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _savePdf(Map<String, dynamic> row) async {
    final issuer = _issuers[_s(row['issuer_id'])];
    if (issuer == null) return _message('No se encuentra el emisor.');
    try {
      await saveDocumentPdf(row, issuer, isQuote: widget.isQuote);
    } catch (error) {
      if (mounted) _message('No se pudo generar el PDF: $error');
    }
  }

  Future<void> _previewPdf(Map<String, dynamic> row) async {
    final issuer = _issuers[_s(row['issuer_id'])];
    if (issuer == null) return _message('No se encuentra el emisor.');
    try {
      final bytes = await buildDocumentPdf(
        row,
        issuer,
        isQuote: widget.isQuote,
      );
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(22),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: math.min(size.width - 44, 1120),
            height: math.min(size.height - 44, 860),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _s(
                            row[widget.isQuote
                                ? 'quote_number'
                                : 'invoice_number'],
                          ),
                          style: Theme.of(dialogContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar visor',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    build: (_) async => bytes,
                    pdfFileName: documentPdfFileName(
                      row,
                      isQuote: widget.isQuote,
                    ),
                    initialPageFormat: PdfPageFormat.a4,
                    maxPageWidth: 900,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowSharing: false,
                    allowPrinting: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _message('No se pudo abrir el visor: $error');
    }
  }

  Future<void> _requestInvoice(Map<String, dynamic> row) async {
    if (_s(row['id']).isEmpty)
      return _message('Este presupuesto no tiene identificador.');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Solicitar factura'),
        content: Text(
          'Se avisará al administrador para crear la factura de ${_s(row['client_name'])}. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _service.requestQuoteInvoice(_s(row['id']));
      if (mounted) {
        _message('Solicitud enviada al administrador.');
        _load();
      }
    } catch (error) {
      if (mounted) _message('No se pudo enviar la solicitud: $error');
    }
  }

  Future<void> _requestModification(Map<String, dynamic> row) async {
    final documentId = _s(row['id']);
    final documentNumber = _s(
      row[widget.isQuote ? 'quote_number' : 'invoice_number'],
    );
    if (documentId.isEmpty || documentNumber.isEmpty) {
      return _message('Este documento no tiene identificador suficiente.');
    }

    final controller = TextEditingController();
    final request = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Solicitar modificación de $documentNumber'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Qué hay que modificar',
              hintText: 'Describe aquí los cambios que necesitas…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (request == null || request.trim().isEmpty) return;

    try {
      await _service.requestDocumentModification(
        documentType: widget.isQuote ? 'quote' : 'invoice',
        documentId: documentId,
        documentNumber: documentNumber,
        requestText: request.trim(),
      );
      if (mounted) _message('Solicitud enviada al administrador.');
    } catch (error) {
      if (mounted) _message('No se pudo enviar la solicitud: $error');
    }
  }

  Future<void> _export() async {
    final rows = _filtered;
    if (!widget.isQuote) {
      await saveBillsExcel(
        sheetName: 'Facturas',
        filePrefix: 'facturas',
        headers: const [
          'Número',
          'Rectifica a',
          'Fecha',
          'Fecha ponencia',
          'Cliente',
          'NIF/CIF',
          'Tipo',
          'Conceptos',
          'Subtotal',
          'IVA',
          'IRPF',
          'Total',
          'Cobrada',
          'Fecha cobro',
        ],
        rows: [
          for (final row in rows)
            [
              _s(row['invoice_number']),
              _s(row['rectified_invoice_number']),
              _s(row['invoice_date']),
              _eventDate(row) ?? '',
              _s(row['client_name']),
              _s(row['client_tax_id']),
              _s(row['invoice_type']),
              (row['line_items'] as List? ?? const [])
                  .map((raw) => _s((raw as Map)['description']))
                  .join(' | '),
              _n(row['subtotal']).toStringAsFixed(2),
              _n(row['vat_amount']).toStringAsFixed(2),
              _n(row['irpf_amount']).toStringAsFixed(2),
              _n(row['total']).toStringAsFixed(2),
              row['paid'] == true ? 'Sí' : 'No',
              _s(row['paid_at']),
            ],
        ],
      );
      return;
    }
    await saveBillsExcel(
      sheetName: 'Presupuestos',
      filePrefix: 'presupuestos',
      headers: [
        'Nº presupuesto',
        'Fecha',
        'Emisor',
        'Cliente',
        'NIF/CIF',
        'Tipo',
        'Subtotal',
        'IVA/IGIC',
        'IRPF',
        'Total',
        'Estado',
      ],
      rows: [
        for (final row in rows)
          [
            _s(row['quote_number']),
            _s(row['quote_date']),
            _s(row['issuer_id']),
            _s(row['client_name']),
            _s(row['client_tax_id']),
            _s(row['invoice_type']),
            _n(row['subtotal']).toStringAsFixed(2),
            _n(row['vat_amount']).toStringAsFixed(2),
            _n(row['irpf_amount']).toStringAsFixed(2),
            _n(row['total']).toStringAsFixed(2),
            _s(row['status']),
          ],
      ],
    );
  }

  Future<void> _downloadStored(
    Map<String, dynamic> row, {
    required String field,
    required String bucket,
    required String fallbackName,
  }) async {
    final path = _s(row[field]);
    if (path.isEmpty) return;
    try {
      final bytes = await _service.downloadStorage(bucket, path);
      final name = path.split('/').last;
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar archivo',
        fileName: name.contains('.') ? name : fallbackName,
        bytes: Uint8List.fromList(bytes),
      );
    } catch (error) {
      if (mounted) _message('No se pudo descargar el archivo: $error');
    }
  }

  Future<void> _markPaid(Map<String, dynamic> row) async {
    final date = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    Uint8List? proof;
    String? proofName;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Marcar ${_s(row['invoice_number'])} como cobrada'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Fecha de cobro (AAAA-MM-DD)',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      withData: true,
                    );
                    if (result != null)
                      setDialogState(() {
                        proof = result.files.single.bytes;
                        proofName = result.files.single.name;
                      });
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(proofName ?? 'Adjuntar justificante (opcional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await _service.markPaid(
      row,
      date.text.trim(),
      proof: proof,
      proofName: proofName,
    );
    _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final number = _s(row[widget.isQuote ? 'quote_number' : 'invoice_number']);
    final confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar $number'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta operación no se puede deshacer. Escribe el número para confirmar.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                decoration: InputDecoration(labelText: number),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, confirmation.text.trim() == number),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _service.deleteDocument(
      widget.isQuote ? 'quotes' : 'invoices',
      _s(row['id']),
    );
    _load();
  }

  Future<void> _rectify(Map<String, dynamic> row) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rectificar ${row['invoice_number']}'),
        content: const Text(
          'Se creará una factura rectificativa con los mismos conceptos e importes en negativo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear rectificativa'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      final now = DateTime.now();
      final date = DateFormat('yyyy-MM-dd').format(now);
      final issuer = _s(row['issuer_id']);
      final seq = await _service.nextRectificativeSequence(issuer, now.year);
      final items = (row['line_items'] as List? ?? const []).map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        item['unit_price'] = -_n(item['unit_price']);
        item['total'] = -_n(item['total']);
        return item;
      }).toList();
      final payload = Map<String, dynamic>.from(row)
        ..remove('id')
        ..remove('created_at')
        ..remove('updated_at')
        ..['invoice_number'] =
            '$issuer-R-${now.year}-${seq.toString().padLeft(3, '0')}'
        ..['invoice_date'] = date
        ..['year'] = now.year
        ..['seq'] = seq
        ..['line_items'] = items
        ..['subtotal'] = -_n(row['subtotal'])
        ..['vat_amount'] = -_n(row['vat_amount'])
        ..['irpf_amount'] = -_n(row['irpf_amount'])
        ..['total'] = -_n(row['total'])
        ..['paid'] = false
        ..['paid_at'] = null
        ..['payment_proof_url'] = null
        ..['is_rectificative'] = true
        ..['rectified_invoice_number'] = row['invoice_number']
        ..['parent_invoice_number'] = row['invoice_number']
        ..['pre_payment_note'] = null
        ..['post_payment_note'] = null;
      await _service.saveInvoice(payload);
      _load();
    } catch (error) {
      if (mounted) _message('No se pudo crear la rectificativa: $error');
    }
  }

  String? _eventDate(Map<String, dynamic> row) {
    final pattern = RegExp(r'(\d{2})/(\d{2})/(\d{4})');
    for (final raw in row['line_items'] as List? ?? const []) {
      final match = pattern.firstMatch(_s((raw as Map)['description']));
      if (match != null)
        return '${match.group(3)}-${match.group(2)}-${match.group(1)}';
    }
    return null;
  }

  DateTime _referenceDate(Map<String, dynamic> row) =>
      DateTime.tryParse(
        _dateBasis == 'ponencia'
            ? (_eventDate(row) ?? _s(row['invoice_date']))
            : _s(row['invoice_date']),
      ) ??
      DateTime.now();

  List<Map<String, dynamic>> get _overdue {
    final unpaid = _rows
        .where((row) => row['issuer_id'] == 'JHE' && row['paid'] != true)
        .toList();
    if (_overdueDays == 'all') return unpaid;
    final cutoff = DateTime.now().subtract(
      Duration(days: int.parse(_overdueDays)),
    );
    return unpaid.where((row) => _referenceDate(row).isBefore(cutoff)).toList();
  }

  Future<void> _selectTypes() async {
    final selected = Set<String>.from(_types);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Tipo de factura'),
          content: SizedBox(
            width: 420,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  'ponencia': 'Ponencia',
                  'mixta': 'Mixta',
                  'complemento': 'Complemento',
                  'formacion': 'Formación',
                  'master': 'Máster',
                  'coworking': 'Coworking',
                  'gastos': 'Gastos',
                  'sponsor': 'Sponsor',
                  'rectificativa': 'Rectificativas',
                }.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: selected.contains(entry.key),
                    onSelected: (value) => setDialog(
                      () => value
                          ? selected.add(entry.key)
                          : selected.remove(entry.key),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialog(() => selected.clear()),
              child: const Text('Todas'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (result != null)
      setState(() {
        _types
          ..clear()
          ..addAll(result);
      });
  }

  Widget _dashboard(NumberFormat money) {
    final overdue = _overdue;
    const groups = <String, ({String label, List<String> types})>{
      'ponencias': (label: 'Ponencias', types: ['ponencia', 'mixta']),
      'gastos': (label: 'Gastos', types: ['gastos']),
      'formaciones': (label: 'Formaciones', types: ['formacion']),
      'master': (label: 'Máster', types: ['master']),
      'coworking': (label: 'Coworking', types: ['coworking']),
      'sponsor': (label: 'Sponsor', types: ['sponsor']),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 65,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFF5B942)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFE56A00),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${overdue.length} pendientes${_overdueDays == 'all' ? '' : ' >${_overdueDays}d'} (${_dateBasis == 'ponencia' ? 'f. ponencia' : 'f. factura'})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF9A3E00),
                                ),
                              ),
                            ),
                            _toggle(
                              'F. factura',
                              _dateBasis == 'invoice',
                              () => setState(() => _dateBasis = 'invoice'),
                            ),
                            const SizedBox(width: 5),
                            _toggle(
                              'F. ponencia',
                              _dateBasis == 'ponencia',
                              () => setState(() => _dateBasis = 'ponencia'),
                            ),
                            const SizedBox(width: 14),
                            for (final value in ['20', '30', 'all']) ...[
                              _toggle(
                                value == 'all' ? 'Todas' : '${value}d',
                                _overdueDays == value,
                                () => setState(() => _overdueDays = value),
                              ),
                              const SizedBox(width: 5),
                            ],
                          ],
                        ),
                        Text(
                          money.format(
                            overdue.fold<double>(
                              0,
                              (sum, row) => sum + _n(row['total']),
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF7C2D00),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final row in overdue)
                                Text(
                                  '${row['invoice_number']} — ${row['client_name']} — ${money.format(_n(row['total']))} — ${DateTime.now().difference(_referenceDate(row)).inDays}d',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Color(0xFFC54F00),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 35,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '↗  Tiempo medio de cobro (días) · desde ${_dateBasis == 'ponencia' ? 'f. ponencia' : 'f. factura'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final group in groups.values)
                            _paymentStat(group.label, group.types),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentStat(String label, List<String> types) {
    final paid = _rows
        .where(
          (row) =>
              row['issuer_id'] == 'JHE' &&
              row['paid'] == true &&
              row['paid_at'] != null &&
              row['is_rectificative'] != true &&
              types.contains(row['invoice_type']),
        )
        .toList();
    final avg = paid.isEmpty
        ? null
        : paid.fold<int>(
                0,
                (sum, row) =>
                    sum +
                    (DateTime.tryParse(_s(row['paid_at'])) ??
                            _referenceDate(row))
                        .difference(_referenceDate(row))
                        .inDays
                        .clamp(0, 9999),
              ) /
              paid.length;
    return Container(
      width: 116,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        border: Border.all(color: const Color(0xFFD4DCE8)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            avg == null ? '—' : avg.round().toString(),
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          Text(
            '${paid.length} cobradas',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool selected, VoidCallback tap) => selected
      ? FilledButton(
          onPressed: tap,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: Text(label),
        )
      : OutlinedButton(
          onPressed: tap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: Text(label),
        );

  Widget _issuerBadge(String issuer) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: issuer == 'BN'
          ? const Color(0xFF9333EA)
          : issuer == 'SKY'
          ? const Color(0xFF0369A1)
          : issuer == 'JHE'
          ? const Color(0xFFEDF1F9)
          : const Color(0xFF334155),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      _issuerLabel(issuer),
      style: TextStyle(
        color: issuer == 'JHE' ? const Color(0xFF142A5C) : Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );

  String _issuerLabel(String issuer) {
    if (issuer == 'JHE') return 'Jon';
    if (issuer == 'BN') return 'Bright';
    if (issuer == 'SKY') return 'Skynet';
    final name = _s(_issuers[issuer]?['name']);
    return name.isEmpty ? issuer : name;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final money = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final compact = MediaQuery.sizeOf(context).width < 760;
    final filterWidth = compact
        ? ((MediaQuery.sizeOf(context).width - 36) / 2).clamp(130, 155)
        : 155.0;
    return Column(
      children: [
        Container(
          height: compact ? 72 : 116,
          color: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 28),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.isQuote ? 'Presupuestos' : 'Facturas emitidas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.headlineMedium)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (!compact && !widget.isQuote && widget.onOpenClients != null)
                OutlinedButton(
                  onPressed: widget.onOpenClients,
                  child: const Text('Ver por clientes'),
                ),
              if (!compact &&
                  !widget.isQuote &&
                  widget.onOpenHistory != null) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenHistory,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Historial'),
                ),
              ],
              if (!compact) const SizedBox(width: 10),
              if (compact)
                IconButton(
                  onPressed: _export,
                  tooltip: 'Exportar Excel',
                  icon: const Icon(Icons.table_view),
                )
              else
                OutlinedButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.table_view),
                  label: const Text('Exportar Excel'),
                ),
              if (widget.isAdmin && widget.isQuote) ...[
                if (!compact) const SizedBox(width: 10),
                if (compact)
                  IconButton(
                    onPressed: () => _edit(),
                    tooltip: 'Nuevo presupuesto',
                    icon: const Icon(Icons.add),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: Text(
                      widget.isQuote ? 'Nuevo presupuesto' : 'Nueva factura',
                    ),
                  ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        if (!widget.isQuote && !compact)
          SizedBox(height: 338, child: _dashboard(money)),
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 28,
            10,
            compact ? 10 : 28,
            10,
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: filterWidth.toDouble(),
                child: TextField(
                  controller: _numberSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nº factura',
                    hintText: 'JHE-...',
                  ),
                ),
              ),
              SizedBox(
                width: filterWidth.toDouble(),
                child: TextField(
                  controller: _clientSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cliente',
                    hintText: 'Cliente...',
                  ),
                ),
              ),
              SizedBox(
                width: filterWidth.toDouble(),
                child: TextField(
                  controller: _conceptSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    hintText: 'Concepto...',
                  ),
                ),
              ),
              _segmented('Emisor', _issuer, {
                'all': 'Todos',
                for (final id in _issuers.keys) id: _issuerLabel(id),
              }, (value) => setState(() => _issuer = value)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tipo de factura',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _selectTypes,
                    icon: const Icon(Icons.filter_list),
                    label: Text(
                      _types.isEmpty ? 'Todas' : '${_types.length} tipos',
                    ),
                  ),
                ],
              ),
              if (!widget.isQuote)
                _segmented('Cobro', _payment, const {
                  'all': 'Todas',
                  'unpaid': 'No cobradas',
                  'paid': 'Cobradas',
                }, (value) => setState(() => _payment = value)),
              IconButton(
                onPressed: _load,
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_selectedRows.isNotEmpty) ...[
                  Text(
                    '${_selectedRows.length} seleccionada${_selectedRows.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 18),
                ],
                if (!widget.isQuote)
                  Text(
                    'Total filtrado: ${money.format(rows.fold<double>(0, (sum, row) => sum + _n(row['total'])))}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Card(
                  margin: EdgeInsets.fromLTRB(
                    compact ? 6 : 24,
                    10,
                    compact ? 6 : 24,
                    compact ? 8 : 24,
                  ),
                  child: rows.isEmpty
                      ? const Center(child: Text('Sin resultados'))
                      : Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                dataRowMinHeight: 58,
                                dataRowMaxHeight: 76,
                                sortColumnIndex: _sortColumnIndex,
                                sortAscending: _sortAscending,
                                headingRowColor: WidgetStatePropertyAll(
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                ),
                                columns: [
                                  DataColumn(
                                    label: Text(
                                      widget.isQuote
                                          ? 'Nº presupuesto'
                                          : 'Nº factura',
                                    ),
                                    onSort: (_, ascending) =>
                                        _setSort('number', ascending),
                                  ),
                                  DataColumn(
                                    label: const Text('Fecha'),
                                    onSort: (_, ascending) =>
                                        _setSort('date', ascending),
                                  ),
                                  if (!widget.isQuote)
                                    DataColumn(
                                      label: const Text('F. ponencia'),
                                      onSort: (_, ascending) =>
                                          _setSort('event', ascending),
                                    ),
                                  DataColumn(
                                    label: const Text('Cliente'),
                                    onSort: (_, ascending) =>
                                        _setSort('client', ascending),
                                  ),
                                  const DataColumn(label: Text('Emisor')),
                                  const DataColumn(label: Text('Tipo')),
                                  DataColumn(
                                    label: const Text('Total'),
                                    numeric: true,
                                    onSort: (_, ascending) =>
                                        _setSort('total', ascending),
                                  ),
                                  const DataColumn(label: Text('Estado')),
                                  const DataColumn(label: Text('Acciones')),
                                ],
                                rows: [
                                  for (final row in rows)
                                    DataRow(
                                      selected: _selectedRows.contains(
                                        _rowId(row),
                                      ),
                                      onSelectChanged: (selected) =>
                                          _selectRow(row, selected ?? false),
                                      cells: [
                                        DataCell(
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _s(
                                                  row[widget.isQuote
                                                      ? 'quote_number'
                                                      : 'invoice_number'],
                                                ),
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (!widget.isQuote &&
                                                  row['is_rectificative'] ==
                                                      true &&
                                                  _s(
                                                    row['rectified_invoice_number'],
                                                  ).isNotEmpty)
                                                Text(
                                                  'Rectifica ${row['rectified_invoice_number']}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _s(
                                              row[widget.isQuote
                                                  ? 'quote_date'
                                                  : 'invoice_date'],
                                            ),
                                          ),
                                        ),
                                        if (!widget.isQuote)
                                          DataCell(
                                            Text(
                                              _eventDate(row) ?? '—',
                                              style: const TextStyle(
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                        DataCell(
                                          SizedBox(
                                            width: 220,
                                            child: Text(
                                              _s(row['client_name']),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          _issuerBadge(_s(row['issuer_id'])),
                                        ),
                                        DataCell(
                                          Text(
                                            row['is_rectificative'] == true
                                                ? 'Rectificativa'
                                                : _typeLabel(
                                                    _s(row['invoice_type']),
                                                  ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _moneyForRow(row),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataCell(_status(row)),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                onPressed: () =>
                                                    _previewPdf(row),
                                                tooltip: 'Ver PDF',
                                                icon: const Icon(
                                                  Icons.visibility_outlined,
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: () => _savePdf(row),
                                                icon: const Icon(
                                                  Icons.file_download_outlined,
                                                  size: 18,
                                                ),
                                                label: const Text('PDF'),
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 10,
                                                      ),
                                                ),
                                              ),
                                              if (widget.isQuote &&
                                                  !widget.isAdmin &&
                                                  row['status'] !=
                                                      'converted' &&
                                                  row['invoice_requested_at'] ==
                                                      null)
                                                OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _requestInvoice(row),
                                                  icon: const Icon(
                                                    Icons.send_outlined,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Solicitar factura',
                                                  ),
                                                ),
                                              if (!widget.isAdmin)
                                                PopupMenuButton<String>(
                                                  tooltip:
                                                      'Solicitar modificación',
                                                  onSelected: (action) {
                                                    if (action ==
                                                        'request_modification') {
                                                      _requestModification(row);
                                                    }
                                                  },
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                      value:
                                                          'request_modification',
                                                      child: ListTile(
                                                        leading: Icon(
                                                          Icons
                                                              .edit_note_outlined,
                                                        ),
                                                        title: Text(
                                                          'Solicitar modificación',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (widget.isAdmin)
                                                PopupMenuButton<String>(
                                                  onSelected: (action) async {
                                                    if (action == 'edit')
                                                      _edit(row: row);
                                                    if (action == 'delete')
                                                      _delete(row);
                                                    if (action == 'paid')
                                                      _markPaid(row);
                                                    if (action == 'undo') {
                                                      await _service.undoPaid(
                                                        row,
                                                      );
                                                      _load();
                                                    }
                                                    if (action == 'rectify')
                                                      _rectify(row);
                                                    if (action == 'convert')
                                                      _edit(seedQuote: row);
                                                    if (action == 'proof')
                                                      _downloadStored(
                                                        row,
                                                        field:
                                                            'payment_proof_url',
                                                        bucket:
                                                            'payment-proofs',
                                                        fallbackName:
                                                            'justificante.pdf',
                                                      );
                                                    if (action == 'source')
                                                      _downloadStored(
                                                        row,
                                                        field: 'source_pdf_url',
                                                        bucket:
                                                            'invoice-sources',
                                                        fallbackName:
                                                            'factura-origen.pdf',
                                                      );
                                                  },
                                                  itemBuilder: (_) => [
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: ListTile(
                                                        leading: Icon(
                                                          Icons.edit,
                                                        ),
                                                        title: Text('Editar'),
                                                      ),
                                                    ),
                                                    if (!widget.isQuote &&
                                                        _s(
                                                          row['source_pdf_url'],
                                                        ).isNotEmpty)
                                                      const PopupMenuItem(
                                                        value: 'source',
                                                        child: ListTile(
                                                          leading: Icon(
                                                            Icons
                                                                .file_download_outlined,
                                                          ),
                                                          title: Text(
                                                            'Descargar PDF de origen',
                                                          ),
                                                        ),
                                                      ),
                                                    if (!widget.isQuote &&
                                                        _s(
                                                          row['payment_proof_url'],
                                                        ).isNotEmpty)
                                                      const PopupMenuItem(
                                                        value: 'proof',
                                                        child: ListTile(
                                                          leading: Icon(
                                                            Icons.attach_file,
                                                          ),
                                                          title: Text(
                                                            'Descargar justificante',
                                                          ),
                                                        ),
                                                      ),
                                                    if (widget.isQuote &&
                                                        row['status'] !=
                                                            'converted')
                                                      const PopupMenuItem(
                                                        value: 'convert',
                                                        child: ListTile(
                                                          leading: Icon(
                                                            Icons.receipt_long,
                                                          ),
                                                          title: Text(
                                                            'Crear factura',
                                                          ),
                                                        ),
                                                      ),
                                                    if (!widget.isQuote &&
                                                        row['paid'] != true)
                                                      const PopupMenuItem(
                                                        value: 'paid',
                                                        child: ListTile(
                                                          leading: Icon(
                                                            Icons
                                                                .payments_outlined,
                                                          ),
                                                          title: Text(
                                                            'Marcar cobrada',
                                                          ),
                                                        ),
                                                      ),
                                                    if (!widget.isQuote &&
                                                        row['paid'] == true)
                                                      const PopupMenuItem(
                                                        value: 'undo',
                                                        child: ListTile(
                                                          leading: Icon(
                                                            Icons.undo,
                                                          ),
                                                          title: Text(
                                                            'Deshacer cobro',
                                                          ),
                                                        ),
                                                      ),
                                                    if (!widget.isQuote &&
                                                        row['is_rectificative'] !=
                                                            true)
                                                      const PopupMenuItem(
                                                        value: 'rectify',
                                                        child: ListTile(
                                                          leading: Icon(
                                                            Icons.rotate_left,
                                                          ),
                                                          title: Text(
                                                            'Rectificar',
                                                          ),
                                                        ),
                                                      ),
                                                    const PopupMenuDivider(),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: ListTile(
                                                        leading: Icon(
                                                          Icons.delete_outline,
                                                          color: Colors.red,
                                                        ),
                                                        title: Text('Eliminar'),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _segmented(
    String label,
    String value,
    Map<String, String> values,
    ValueChanged<String> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 5,
        children: [
          for (final entry in values.entries)
            entry.key == value
                ? FilledButton(
                    onPressed: () => changed(entry.key),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 14,
                      ),
                    ),
                    child: Text(entry.value),
                  )
                : OutlinedButton(
                    onPressed: () => changed(entry.key),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 14,
                      ),
                    ),
                    child: Text(entry.value),
                  ),
        ],
      ),
    ],
  );

  Widget _status(Map<String, dynamic> row) {
    if (widget.isQuote) {
      final converted = row['status'] == 'converted';
      final requested =
          row['status'] == 'invoice_requested' ||
          row['invoice_requested_at'] != null;
      return Chip(
        label: Text(
          converted
              ? 'Convertido'
              : requested
              ? 'Factura solicitada'
              : 'Borrador',
        ),
        avatar: Icon(
          converted
              ? Icons.check
              : requested
              ? Icons.notifications_active_outlined
              : Icons.edit_note,
          size: 16,
        ),
      );
    }
    final paid = row['paid'] == true;
    if (paid) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF059669),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  _s(row['paid_at']),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_s(row['payment_proof_url']).isNotEmpty)
            IconButton(
              tooltip: 'Descargar justificante',
              onPressed: () => _downloadStored(
                row,
                field: 'payment_proof_url',
                bucket: 'payment-proofs',
                fallbackName: 'justificante.pdf',
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
            ),
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Deshacer cobro',
              onPressed: () async {
                await _service.undoPaid(row);
                _load();
              },
              icon: const Icon(Icons.undo, size: 19),
            ),
        ],
      );
    }
    if (widget.isAdmin)
      return OutlinedButton.icon(
        onPressed: () => _markPaid(row),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Cobrada'),
      );
    return const Chip(
      label: Text('Pendiente'),
      avatar: Icon(Icons.schedule, size: 16, color: Colors.orange),
    );
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

String _s(dynamic value) => value?.toString() ?? '';
double _n(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String _moneyForRow(Map<String, dynamic> row) {
  final code = _s(row['currency']).toUpperCase();
  final symbol = code == 'USD' || code == 'GBP' ? '$code ' : '€';
  return NumberFormat.currency(
    locale: 'es_ES',
    name: code == 'USD' || code == 'GBP' ? code : 'EUR',
    symbol: symbol,
  ).format(_n(row['total']));
}

String _typeLabel(String value) => switch (value) {
  'ponencia' => 'Ponencia',
  'complemento' => 'Complemento',
  'sponsor' => 'Sponsor',
  'formacion' => 'Formación',
  'master' => 'Máster',
  'coworking' => 'Coworking',
  'gastos' => 'Gastos',
  'mixta' => 'Mixta',
  _ => value,
};
