import 'package:flutter/material.dart';

import '../app.dart';
import '../services/bills_service.dart';

class PonenciasPage extends StatefulWidget {
  const PonenciasPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<PonenciasPage> createState() => _PonenciasPageState();
}

class _PonenciasPageState extends State<PonenciasPage> {
  final _service = BillsService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.billingRequestPonencias();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _rows;
    return _rows.where((row) {
      final haystack = [
        row['company'],
        row['contact'],
        row['status'],
        row['date'],
        row['address'],
        row['description'],
        row['details'],
      ].map(_s).join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>> get _tree {
    final result =
        <String, Map<String, Map<String, List<Map<String, dynamic>>>>>{};
    for (final row in _filtered) {
      final date = _dateInfo(_s(row['date']));
      final year = date['year'] ?? 'Sin fecha';
      final month = date['month'] ?? 'Sin fecha';
      final company = _s(row['company']).isEmpty
          ? 'Empresa sin nombre'
          : _s(row['company']);
      result.putIfAbsent(year, () => {});
      result[year]!.putIfAbsent(month, () => {});
      result[year]![month]!.putIfAbsent(company, () => []);
      result[year]![month]![company]!.add(row);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    return Scaffold(
      backgroundColor: billsSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Árbol de ponencias'),
        leading: widget.onBack == null
            ? null
            : IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
          IconButton(
            tooltip: 'Actualizar desde Supabase',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Administración · datos locales',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.cloud_done_outlined, size: 16),
                    label: Text('${_filtered.length} ponencias'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Año → mes → empresa → fecha. Los honorarios, gastos y comunicaciones se conservan dentro de cada evento.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Buscar empresa, persona, estado o fecha',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _search.clear,
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(child: _body(tree)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>> tree,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 46,
                  color: Color(0xFFB42318),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No se pudieron leer las ponencias',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_rows.isEmpty)
      return const Center(child: Text('No hay ponencias para mostrar.'));
    final years = tree.keys.toList()
      ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    return ListView(
      children: [
        for (final year in years)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(
                Icons.calendar_today_outlined,
                color: billsNavy,
              ),
              title: Text(
                year,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              subtitle: Text('${_countYear(tree[year]!)} ponencias'),
              children: [
                for (final month in _sorted(tree[year]!.keys))
                  _monthTile(year, month, tree[year]![month]!),
              ],
            ),
          ),
      ],
    );
  }

  Widget _monthTile(
    String year,
    String month,
    Map<String, List<Map<String, dynamic>>> companies,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 12, bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.date_range_outlined, size: 20),
        title: Text(month, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_countCompanies(companies)} empresas'),
        children: [
          for (final company in _sorted(companies.keys))
            _companyTile(company, companies[company]!),
        ],
      ),
    );
  }

  Widget _companyTile(String company, List<Map<String, dynamic>> rows) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, right: 8, bottom: 6),
      child: ExpansionTile(
        leading: const Icon(Icons.business_outlined, size: 20),
        title: Text(
          company,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${rows.length} registro${rows.length == 1 ? '' : 's'}'),
        children: [for (final row in rows) _eventCard(row)],
      ),
    );
  }

  Widget _eventCard(Map<String, dynamic> row) {
    final status = _s(row['status']);
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 8, bottom: 8),
      child: Card(
        color: const Color(0xFFF8FAFC),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.mic_none_outlined,
                    size: 19,
                    color: billsNavy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _s(row['date']).isEmpty
                          ? 'Fecha sin indicar'
                          : _s(row['date']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _status(status),
                ],
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  if (_s(row['contact']).isNotEmpty)
                    _detail(Icons.person_outline, _s(row['contact'])),
                  if (_s(row['address']).isNotEmpty)
                    _detail(Icons.place_outlined, _s(row['address'])),
                  if (_s(row['fee']).isNotEmpty)
                    _detail(
                      Icons.euro_outlined,
                      'Honorarios: ${_s(row['fee'])}',
                    ),
                  if (_s(row['expenses']).isNotEmpty)
                    _detail(
                      Icons.luggage_outlined,
                      'Gastos: ${_s(row['expenses'])}',
                    ),
                  if (_s(row['invoice']).isNotEmpty)
                    _detail(Icons.receipt_long_outlined, _s(row['invoice'])),
                ],
              ),
              if (_s(row['description']).isNotEmpty ||
                  _s(row['details']).isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _s(row['description']).isNotEmpty
                      ? _s(row['description'])
                      : _s(row['details']),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFE8EEF9),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.isEmpty ? 'Sin estado' : status,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: billsNavy,
      ),
    ),
  );

  Widget _detail(IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: const Color(0xFF64748B)),
      const SizedBox(width: 5),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Text(value, overflow: TextOverflow.ellipsis),
      ),
    ],
  );

  int _countYear(Map<String, Map<String, List<Map<String, dynamic>>>> months) =>
      months.values.fold(
        0,
        (total, companies) => total + _countCompanies(companies),
      );
  int _countCompanies(Map<String, List<Map<String, dynamic>>> companies) =>
      companies.values.fold(0, (total, rows) => total + rows.length);
  List<String> _sorted(Iterable<String> values) =>
      values.toList()..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
  String _sortKey(String value) => value == 'Sin fecha' ? '9999' : value;
  String _s(dynamic value) => (value ?? '').toString().trim();

  Map<String, String> _dateInfo(String value) {
    final match = RegExp(r'^(\d{1,2})\/(\d{1,2})\/(\d{4})').firstMatch(value);
    if (match == null) return {'year': 'Sin fecha', 'month': 'Sin fecha'};
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    final month = int.tryParse(match.group(2)!) ?? 0;
    return {
      'year': match.group(3)!,
      'month': month >= 1 && month <= 12
          ? '${match.group(2)!.padLeft(2, '0')} · ${months[month - 1]}'
          : 'Sin fecha',
    };
  }
}
