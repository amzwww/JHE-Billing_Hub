import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import '../services/pdf_service.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key, required this.isAdmin, this.onBack});
  final bool isAdmin;
  final VoidCallback? onBack;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _service = BillsService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _invoices = [];
  Map<String, Map<String, dynamic>> _issuers = {};
  bool _loading = true;
  String _issuer = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _service.invoices(),
        _service.issuers(),
      ]);
      if (mounted) {
        setState(() {
          _invoices = values[0];
          _issuers = {for (final row in values[1]) row['id'].toString(): row};
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ClientGroup> get _groups {
    final groups = <String, _ClientGroup>{};
    for (final invoice in _invoices) {
      final name = _s(invoice['client_name']).trim();
      if (name.isEmpty) continue;
      final key = '${invoice['issuer_id']}::${name.toLowerCase()}';
      final group = groups.putIfAbsent(
        key,
        () => _ClientGroup(
          key: key,
          name: name,
          taxId: _s(invoice['client_tax_id']),
          issuerId: _s(invoice['issuer_id']),
        ),
      );
      group.invoices.add(invoice);
      group.total += _n(invoice['total']);
      if (invoice['paid'] == true) {
        group.paid += _n(invoice['total']);
      } else {
        group.pending += _n(invoice['total']);
      }
    }
    final query = _search.text.trim().toLowerCase();
    final result =
        groups.values
            .where(
              (group) =>
                  (_issuer == 'all' || group.issuerId == _issuer) &&
                  (query.isEmpty ||
                      group.name.toLowerCase().contains(query) ||
                      group.taxId.toLowerCase().contains(query)),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  int get _allGroupCount => _invoices
      .where((row) => _s(row['client_name']).trim().isNotEmpty)
      .map(
        (row) =>
            '${row['issuer_id']}::${_s(row['client_name']).trim().toLowerCase()}',
      )
      .toSet()
      .length;

  Future<void> _details(_ClientGroup group) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(group.name)),
            if (widget.isAdmin)
              IconButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _edit(group);
                },
                icon: const Icon(Icons.edit),
                tooltip: 'Editar cliente',
              ),
          ],
        ),
        content: SizedBox(
          width: 920,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${group.invoices.length} facturas · Cobrado ${_money(group.paid)} · Pendiente ${_money(group.pending)} · Total ${_money(group.total)}',
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Número')),
                      DataColumn(label: Text('Fecha')),
                      DataColumn(label: Text('Tipo')),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('PDF')),
                    ],
                    rows: [
                      for (final invoice in group.invoices)
                        DataRow(
                          cells: [
                            DataCell(Text(_s(invoice['invoice_number']))),
                            DataCell(Text(_s(invoice['invoice_date']))),
                            DataCell(Text(_s(invoice['invoice_type']))),
                            DataCell(Text(_money(_n(invoice['total'])))),
                            DataCell(
                              Text(
                                invoice['paid'] == true
                                    ? 'Cobrada'
                                    : 'Pendiente',
                              ),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf),
                                onPressed: () async {
                                  final issuer =
                                      _issuers[_s(invoice['issuer_id'])];
                                  if (issuer != null)
                                    await saveDocumentPdf(
                                      invoice,
                                      issuer,
                                      isQuote: false,
                                    );
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(_ClientGroup group) async {
    final sample = group.invoices.first;
    final name = TextEditingController(text: group.name);
    final taxId = TextEditingController(text: group.taxId);
    final address1 = TextEditingController(
      text: _s(sample['client_address_line1']),
    );
    final address2 = TextEditingController(
      text: _s(sample['client_address_line2']),
    );
    final city = TextEditingController(text: _s(sample['client_city_zip']));
    final country = TextEditingController(text: _s(sample['client_country']));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar datos del cliente'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text(
                  'Los cambios se aplicarán a ${group.invoices.length} facturas.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre / razón social',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: taxId,
                  decoration: const InputDecoration(labelText: 'NIF / CIF'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address1,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address2,
                  decoration: const InputDecoration(labelText: 'Dirección 2'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: city,
                  decoration: const InputDecoration(labelText: 'CP y ciudad'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: country,
                  decoration: const InputDecoration(labelText: 'País'),
                ),
              ],
            ),
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
    );
    if (accepted != true) return;
    await _service.updateClient(
      [for (final invoice in group.invoices) _s(invoice['id'])],
      {
        'client_name': name.text.trim(),
        'client_tax_id': _null(taxId.text),
        'client_address_line1': _null(address1.text),
        'client_address_line2': _null(address2.text),
        'client_city_zip': _null(city.text),
        'client_country': _null(country.text),
      },
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Column(
      children: [
        Container(
          height: 116,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28),
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
                  'Clientes',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${groups.length} de $_allGroupCount',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 6),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 540,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filtrar por nombre de cliente...',
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD4DCE8)),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _issuerButton('all', 'Todos'),
                    for (final id in _issuers.keys)
                      _issuerButton(id, _issuerLabel(id)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Card(
                  margin: const EdgeInsets.fromLTRB(28, 16, 28, 28),
                  child: groups.isEmpty
                      ? const Center(child: Text('Sin clientes'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowColor: WidgetStatePropertyAll(
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                              ),
                              columns: const [
                                DataColumn(label: Text('Cliente')),
                                DataColumn(label: Text('Emisor')),
                                DataColumn(label: Text('NIF/CIF')),
                                DataColumn(
                                  label: Text('Facturas'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('Cobrado'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('Pendiente'),
                                  numeric: true,
                                ),
                                DataColumn(label: Text('Total'), numeric: true),
                              ],
                              rows: [
                                for (final group in groups)
                                  DataRow(
                                    onSelectChanged: (_) => _details(group),
                                    cells: [
                                      DataCell(
                                        Text(
                                          group.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      DataCell(_issuerBadge(group.issuerId)),
                                      DataCell(Text(group.taxId)),
                                      DataCell(
                                        Text('${group.invoices.length}'),
                                      ),
                                      DataCell(
                                        Text(
                                          _money(group.paid),
                                          style: const TextStyle(
                                            color: Color(0xFF00A676),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _money(group.pending),
                                          style: const TextStyle(
                                            color: Color(0xFFE56A00),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _money(group.total),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
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
      ],
    );
  }

  Widget _issuerButton(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 3),
    child: value == _issuer
        ? FilledButton(
            onPressed: () => setState(() => _issuer = value),
            child: Text(label),
          )
        : TextButton(
            onPressed: () => setState(() => _issuer = value),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
  );

  Widget _issuerBadge(String issuer) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: issuer == 'BN'
          ? const Color(0xFF9333EA)
          : issuer == 'SKY'
          ? const Color(0xFF0369A1)
          : issuer == 'JHE'
          ? const Color(0xFFEDF1F9)
          : const Color(0xFF334155),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      _issuerLabel(issuer),
      style: TextStyle(
        color: issuer == 'JHE' ? const Color(0xFF142A5C) : Colors.white,
        fontWeight: FontWeight.w700,
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
}

class _ClientGroup {
  _ClientGroup({
    required this.key,
    required this.name,
    required this.taxId,
    required this.issuerId,
  });
  final String key;
  final String name;
  final String taxId;
  final String issuerId;
  final List<Map<String, dynamic>> invoices = [];
  double total = 0;
  double paid = 0;
  double pending = 0;
}

String _s(dynamic value) => value?.toString() ?? '';
double _n(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String _money(double value) =>
    NumberFormat.currency(locale: 'es_ES', symbol: '€').format(value);
String? _null(String value) => value.trim().isEmpty ? null : value.trim();
