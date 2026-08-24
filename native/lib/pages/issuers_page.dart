import 'package:flutter/material.dart';

import '../services/bills_service.dart';

class IssuersPage extends StatefulWidget {
  const IssuersPage({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<IssuersPage> createState() => _IssuersPageState();
}

class _IssuersPageState extends State<IssuersPage> {
  final _service = BillsService();
  final Map<String, Map<String, TextEditingController>> _forms = {};
  bool _loading = true;
  String? _saving;

  static const _keys = [
    'name',
    'tax_id',
    'address_line1',
    'address_line2',
    'city_zip',
    'phone',
    'email',
    'ccc',
    'iban',
    'swift',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _service.issuers();
    for (final fields in _forms.values) {
      for (final controller in fields.values) controller.dispose();
    }
    _forms.clear();
    for (final row in rows) {
      _forms[row['id'].toString()] = {
        for (final key in _keys)
          key: TextEditingController(text: row[key]?.toString() ?? ''),
      };
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final fields in _forms.values) {
      for (final controller in fields.values) controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String id) async {
    setState(() => _saving = id);
    try {
      final fields = _forms[id]!;
      await _service.updateIssuer(id, {
        for (final entry in fields.entries)
          entry.key: entry.value.text.trim().isEmpty
              ? null
              : entry.value.text.trim(),
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$id guardado')));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _addIssuer() async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo emisor'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: idController, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Código corto', hintText: 'EJ. ACME')),
              const SizedBox(height: 12),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre del emisor')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final id = idController.text.trim().toUpperCase();
              final name = nameController.text.trim();
              if (id.isEmpty || name.isEmpty) return;
              Navigator.pop(dialogContext, (id, name));
            },
            child: const Text('Dar de alta'),
          ),
        ],
      ),
    );
    idController.dispose();
    nameController.dispose();
    if (values == null) return;
    try {
      await _service.createIssuer(values.$1, {'name': values.$2, 'tax_id': 'Pendiente', 'address_line1': 'Pendiente', 'city_zip': 'Pendiente'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Emisor dado de alta. Completa ahora sus datos.')));
      _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo dar de alta: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const Text(
                'Datos de los emisores',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              FilledButton.icon(onPressed: _addIssuer, icon: const Icon(Icons.add_business_outlined), label: const Text('Nuevo emisor')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 30,
                    horizontal: 28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                        children: [
                          for (final entry in _forms.entries) ...[
                            _issuerForm(entry.key, entry.value),
                            const SizedBox(height: 28),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _issuerForm(
    String id,
    Map<String, TextEditingController> fields,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$id · ${fields['name']!.text}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _field(fields['name']!, 'Nombre / Razón social')),
              const SizedBox(width: 18),
              Expanded(child: _field(fields['tax_id']!, 'CIF/NIF')),
            ],
          ),
          const SizedBox(height: 18),
          _field(fields['address_line1']!, 'Dirección'),
          const SizedBox(height: 18),
          _field(fields['address_line2']!, 'Dirección 2'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _field(fields['city_zip']!, 'CP y ciudad')),
              const SizedBox(width: 18),
              Expanded(child: _field(fields['phone']!, 'Teléfono')),
            ],
          ),
          const SizedBox(height: 18),
          _field(fields['ccc']!, 'CCC'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _field(fields['iban']!, 'IBAN')),
              const SizedBox(width: 18),
              Expanded(child: _field(fields['swift']!, 'Swift')),
            ],
          ),
          const SizedBox(height: 18),
          _field(fields['email']!, 'Email'),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving == null ? () => _save(id) : null,
              icon: _saving == id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text('Guardar $id'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(TextEditingController controller, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(controller: controller),
    ],
  );
}
