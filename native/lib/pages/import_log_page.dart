import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';

class ImportLogPage extends StatefulWidget {
  const ImportLogPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<ImportLogPage> createState() => _ImportLogPageState();
}

class _ImportLogPageState extends State<ImportLogPage> {
  final _service = BillsService();
  final _search = TextEditingController();
  final _money = NumberFormat.currency(locale: 'es_ES', symbol: '€');
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

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
    final rows = await _service.importLog();
    if (mounted)
      setState(() {
        _rows = rows;
        _loading = false;
      });
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      final data = row['imported_data'] is Map
          ? Map<String, dynamic>.from(row['imported_data'] as Map)
          : <String, dynamic>{};
      return query.isEmpty ||
          '${row['invoice_number']} ${row['source_pdf_name']} ${data['client_name']}'
              .toLowerCase()
              .contains(query);
    }).toList();
  }

  Future<void> _download(Map<String, dynamic> row) async {
    final path = row['source_pdf_url']?.toString();
    if (path == null || path.isEmpty) return;
    try {
      final bytes = await _service.downloadStorage('invoice-sources', path);
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar PDF de origen',
        fileName: row['source_pdf_name']?.toString() ?? 'origen.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: Uint8List.fromList(bytes),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo descargar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Historial de importaciones',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text('${rows.length} de ${_rows.length} registros'),
                  ],
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Número, cliente o archivo',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Card(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: rows.isEmpty
                      ? const Center(child: Text('Sin registros'))
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
                                DataColumn(label: Text('Fecha')),
                                DataColumn(label: Text('Nº factura')),
                                DataColumn(label: Text('Cliente')),
                                DataColumn(label: Text('Acción')),
                                DataColumn(label: Text('Total'), numeric: true),
                                DataColumn(label: Text('PDF origen')),
                              ],
                              rows: [for (final row in rows) _dataRow(row)],
                            ),
                          ),
                        ),
                ),
        ),
      ],
    );
  }

  DataRow _dataRow(Map<String, dynamic> row) {
    final data = row['imported_data'] is Map
        ? Map<String, dynamic>.from(row['imported_data'] as Map)
        : <String, dynamic>{};
    final parsed = DateTime.tryParse(row['imported_at']?.toString() ?? '');
    return DataRow(
      cells: [
        DataCell(
          Text(
            parsed == null
                ? ''
                : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal()),
          ),
        ),
        DataCell(Text(row['invoice_number']?.toString() ?? '')),
        DataCell(Text(data['client_name']?.toString() ?? '—')),
        DataCell(Chip(label: Text(row['action']?.toString() ?? ''))),
        DataCell(
          Text(
            data['total'] == null
                ? '—'
                : _money.format(double.tryParse(data['total'].toString()) ?? 0),
          ),
        ),
        DataCell(
          row['source_pdf_url'] == null
              ? const Text('Sin archivo')
              : IconButton(
                  onPressed: () => _download(row),
                  icon: const Icon(Icons.download),
                  tooltip: 'Guardar PDF',
                ),
        ),
      ],
    );
  }
}
