import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import 'billing_request_editor_page.dart';
import 'document_editor_page.dart';

class BillingRequestsPage extends StatefulWidget {
  const BillingRequestsPage({
    super.key,
    required this.isAdmin,
    required this.onBack,
    this.onChanged,
    this.onNewQuote,
    this.canManageRequests = true,
  });

  final bool isAdmin;
  final bool canManageRequests;
  final VoidCallback onBack;
  final VoidCallback? onChanged;
  final Future<void> Function()? onNewQuote;

  @override
  State<BillingRequestsPage> createState() => _BillingRequestsPageState();
}

class _BillingRequestsPageState extends State<BillingRequestsPage> {
  final _service = BillsService();
  final _companyFilter = TextEditingController();
  final _contactFilter = TextEditingController();
  final _populationFilter = TextEditingController();
  final _dateFilter = TextEditingController();
  final _tableHorizontalScroll = ScrollController();
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _issuers = [];
  bool _loading = true;
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  String _sortKey = 'updated_at';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _companyFilter,
      _contactFilter,
      _populationFilter,
      _dateFilter,
    ]) {
      controller.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _companyFilter,
      _contactFilter,
      _populationFilter,
      _dateFilter,
    ]) {
      controller.dispose();
    }
    _tableHorizontalScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _service.billingRequests(),
        _service.issuers(),
      ]);
      if (mounted) {
        setState(() {
          _rows = values[0];
          _issuers = values[1];
        });
        widget.onChanged?.call();
      }
    } catch (error) {
      if (mounted) _message('No se pudieron cargar las gestiones: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final company = _companyFilter.text.trim().toLowerCase();
    final contact = _contactFilter.text.trim().toLowerCase();
    final population = _populationFilter.text.trim().toLowerCase();
    final date = _dateFilter.text.trim().toLowerCase();
    final rows = _rows.where((row) {
      return (_statusFilter == 'all' || row['status'] == _statusFilter) &&
          (_typeFilter == 'all' || row['request_type'] == _typeFilter) &&
          (_contains(row['company_name'], company)) &&
          (_contains(row['contact_name'], contact)) &&
          (_contains(row['presentation_population'], population)) &&
          (_contains(row['presentation_date'], date));
    }).toList();
    dynamic sortValue(Map<String, dynamic> row) => switch (_sortKey) {
      'status' => _s(row['status']),
      'type' => _s(row['request_type']),
      'invoice' => _s(row['invoice_number']).toLowerCase(),
      'company' => _s(row['company_name']).toLowerCase(),
      'contact' => _s(row['contact_name']).toLowerCase(),
      'date' => _s(row['presentation_date']),
      'population' => _s(row['presentation_population']).toLowerCase(),
      'amount' => _n(row['presentation_amount']),
      _ => _s(row['updated_at']),
    };
    rows.sort((left, right) {
      final a = sortValue(left);
      final b = sortValue(right);
      final result = a is num && b is num
          ? a.compareTo(b)
          : a.toString().compareTo(b.toString());
      return _sortAscending ? result : -result;
    });
    return rows;
  }

  bool _contains(dynamic value, String query) =>
      query.isEmpty || _s(value).toLowerCase().contains(query);

  Future<void> _newRequest() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BillingRequestEditorPage(isAdmin: widget.isAdmin),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BillingRequestEditorPage(existing: row, isAdmin: widget.isAdmin),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _duplicate(Map<String, dynamic> row) async {
    try {
      await _service.duplicateBillingRequest(row);
      if (mounted) {
        _message('Entrada duplicada como Pendiente.');
        _load();
      }
    } catch (error) {
      if (mounted) _message('No se pudo duplicar: $error');
    }
  }

  Future<void> _createInvoice(Map<String, dynamic> row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentEditorPage(
          isQuote: false,
          billingRequest: row,
          initialIssuer: _s(row['invoice_issuer']).isEmpty
              ? 'JHE'
              : _s(row['invoice_issuer']),
          initialType: _s(row['request_type']).isEmpty
              ? 'ponencia'
              : _s(row['request_type']),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _changeStatus(Map<String, dynamic> row, String value) async {
    final previous = _s(row['status']);
    if (previous == value) return;
    String? issuer = _s(row['invoice_issuer']).isEmpty
        ? null
        : _s(row['invoice_issuer']);
    if (value == 'a_facturar') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar A facturar'),
          content: const Text(
            'Recuerda que esto envía un aviso a facturación. ¿Quieres continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      if (!mounted) return;
      issuer = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Emisor de la factura'),
          content: const Text('¿Quién emitirá esta factura?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            for (final issuerRow in _issuers)
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _s(issuerRow['id'])),
                child: Text(_issuerLabel(issuerRow)),
              ),
          ],
        ),
      );
      if (issuer == null) return;
    } else if (value != 'a_facturar') {
      issuer = null;
    }
    try {
      await _service.updateBillingRequestStatus(
        _s(row['id']),
        value,
        issuer: issuer,
      );
      _load();
    } catch (error) {
      if (mounted) _message('No se pudo cambiar el estado: $error');
    }
  }

  String _issuerLabel(Map<String, dynamic> issuer) {
    final id = _s(issuer['id']);
    if (id == 'JHE') return 'Jon';
    if (id == 'BN') return 'Bright';
    if (id == 'SKY') return 'Skynet';
    final name = _s(issuer['name']);
    return name.isEmpty ? id : name;
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar gestión'),
        content: Text('¿Eliminar la gestión de ${_s(row['company_name'])}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await _service.deleteBillingRequest(_s(row['id']));
      _load();
    } catch (error) {
      if (mounted) _message('No se pudo eliminar: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final toInvoice = _rows
        .where((row) => row['status'] == 'a_facturar')
        .length;
    final toCollect = _rows.where((row) => row['status'] == 'a_cobrar').length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Gestiones administrativas'),
        actions: [
          if (!compact && toInvoice > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FilterChip(
                avatar: const Icon(
                  Icons.notifications_active_outlined,
                  size: 17,
                ),
                label: Text('A facturar ($toInvoice)'),
                selected: _statusFilter == 'a_facturar',
                onSelected: (_) => _toggleStatusFilter('a_facturar'),
              ),
            ),
          if (!compact && toCollect > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FilterChip(
                avatar: const Icon(Icons.payments_outlined, size: 17),
                label: Text('$toCollect a cobrar'),
                selected: _statusFilter == 'a_cobrar',
                onSelected: (_) => _toggleStatusFilter('a_cobrar'),
              ),
            ),
          IconButton(
            onPressed: _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onNewQuote != null)
            if (compact)
              IconButton(
                onPressed: widget.onNewQuote,
                tooltip: 'Nuevo presupuesto',
                icon: const Icon(Icons.request_quote_outlined),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton.icon(
                  onPressed: widget.onNewQuote,
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text('Nuevo presupuesto'),
                ),
              ),
          if (compact)
            IconButton(
              onPressed: widget.canManageRequests ? _newRequest : null,
              tooltip: 'Nueva solicitud',
              icon: const Icon(Icons.add),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 20, left: 8),
              child: FilledButton.icon(
                onPressed: widget.canManageRequests ? _newRequest : null,
                icon: const Icon(Icons.add),
                label: const Text('Nueva solicitud'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (compact && (toInvoice > 0 || toCollect > 0))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (toInvoice > 0)
                    FilterChip(
                      avatar: const Icon(
                        Icons.notifications_active_outlined,
                        size: 17,
                      ),
                      label: Text('A facturar ($toInvoice)'),
                      selected: _statusFilter == 'a_facturar',
                      onSelected: (_) => _toggleStatusFilter('a_facturar'),
                    ),
                  if (toCollect > 0)
                    FilterChip(
                      avatar: const Icon(Icons.payments_outlined, size: 17),
                      label: Text('$toCollect a cobrar'),
                      selected: _statusFilter == 'a_cobrar',
                      onSelected: (_) => _toggleStatusFilter('a_cobrar'),
                    ),
                ],
              ),
            ),
          _filters(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? const Center(
                    child: Text('No hay gestiones con estos filtros.'),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 8 : 24,
                      compact ? 12 : 24,
                      compact ? 8 : 24,
                      12,
                    ),
                    child: Scrollbar(
                      controller: _tableHorizontalScroll,
                      thumbVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _tableHorizontalScroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(child: _table()),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
    child: Wrap(
      spacing: 14,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _filterField(_companyFilter, 'Filtrar empresa', 210),
        _filterField(_contactFilter, 'Filtrar contacto', 190),
        _filterField(_populationFilter, 'Filtrar población', 180),
        _filterField(_dateFilter, 'Filtrar fecha', 150),
        _filterDropdown(
          'Estado',
          _statusFilter,
          billingRequestStatuses,
          (value) => setState(() => _statusFilter = value ?? 'all'),
        ),
        _filterDropdown(
          'Tipo',
          _typeFilter,
          billingRequestTypes,
          (value) => setState(() => _typeFilter = value ?? 'all'),
        ),
        Text(
          '${_filtered.length} gestiones',
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
      ],
    ),
  );

  void _toggleStatusFilter(String status) {
    setState(() => _statusFilter = _statusFilter == status ? 'all' : status);
  }

  Widget _filterField(
    TextEditingController controller,
    String label,
    double width,
  ) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
      ),
    ),
  );

  Widget _filterDropdown(
    String label,
    String value,
    Map<String, String> values,
    ValueChanged<String?> changed,
  ) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('Todos')),
        for (final entry in values.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: changed,
    ),
  );

  Widget _table() {
    final rows = _filtered;
    final sortIndex = switch (_sortKey) {
      'invoice' => 1,
      'status' => 2,
      'type' => 3,
      'company' => 4,
      'contact' => 5,
      'date' => 6,
      'population' => 7,
      'amount' => 8,
      _ => 0,
    };
    DataColumn column(String label, String key) => DataColumn(
      label: Text(label),
      onSort: (_, ascending) => setState(() {
        _sortKey = key;
        _sortAscending = ascending;
      }),
    );
    return DataTable(
      sortColumnIndex: sortIndex,
      sortAscending: _sortAscending,
      headingRowColor: const WidgetStatePropertyAll(Colors.white),
      columns: [
        const DataColumn(label: Text('Ficha')),
        column('Nº factura', 'invoice'),
        column('Estado', 'status'),
        column('Tipo', 'type'),
        column('Nombre empresa', 'company'),
        column('Persona de contacto', 'contact'),
        column('Fecha ponencia', 'date'),
        column('Población', 'population'),
        column('Importe', 'amount'),
        const DataColumn(label: Text('Acciones')),
      ],
      rows: [for (final row in rows) _row(row)],
    );
  }

  DataRow _row(Map<String, dynamic> row) {
    final amount = _n(row['presentation_amount']);
    final expenses = _n(row['logistics_expenses']);
    return DataRow(
      cells: [
        DataCell(
          TextButton.icon(
            onPressed: widget.canManageRequests ? () => _edit(row) : null,
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text('Ver y editar'),
          ),
        ),
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              _s(row['invoice_number']).isEmpty
                  ? '—'
                  : _s(row['invoice_number']),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(_statusDropdown(row)),
        DataCell(
          Text(billingRequestTypes[_s(row['request_type'])] ?? 'Ponencia'),
        ),
        DataCell(
          SizedBox(
            width: 220,
            child: Text(
              _s(row['company_name']),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 190,
            child: Text(
              '${_s(row['contact_name'])}\n${_s(row['contact_email'])}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(_formatDate(row['presentation_date']))),
        DataCell(Text(_s(row['presentation_population']))),
        DataCell(
          Text(
            '${amount.toStringAsFixed(2)} €\nGastos: ${expenses.toStringAsFixed(2)} €',
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.canManageRequests)
                IconButton(
                  onPressed: () => _edit(row),
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (widget.canManageRequests)
                IconButton(
                  onPressed: () => _duplicate(row),
                  tooltip: 'Duplicar entrada',
                  icon: const Icon(Icons.copy_outlined),
                ),
              if (widget.isAdmin && row['status'] == 'a_facturar')
                FilledButton.icon(
                  onPressed: () => _createInvoice(row),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('Generar factura'),
                ),
              if (widget.canManageRequests)
                IconButton(
                  onPressed: () => _delete(row),
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusDropdown(Map<String, dynamic> row) {
    final value = billingRequestStatuses.containsKey(_s(row['status']))
        ? _s(row['status'])
        : 'pendiente';
    if (!widget.canManageRequests) return _statusChip(value);
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      items: [
        for (final entry in billingRequestStatuses.entries)
          DropdownMenuItem(value: entry.key, child: _statusChip(entry.key)),
      ],
      onChanged: (next) {
        if (next != null) _changeStatus(row, next);
      },
    );
  }

  Widget _statusChip(String value) {
    final color = switch (value) {
      'a_facturar' => const Color(0xFFB45309),
      'a_cobrar' => const Color(0xFF2563EB),
      'cobrada' => const Color(0xFF059669),
      'no_viable' || 'cancelada' => const Color(0xFF64748B),
      _ => const Color(0xFF7C3AED),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        billingRequestStatuses[value] ?? value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(_s(value));
    return parsed == null
        ? _s(value)
        : DateFormat('dd/MM/yyyy').format(parsed.toLocal());
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

String _s(dynamic value) => value?.toString() ?? '';
double _n(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse('$value'.replaceAll(',', '.')) ?? 0;
