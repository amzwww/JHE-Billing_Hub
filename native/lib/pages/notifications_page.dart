import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = BillsService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _service.notifications();
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) _message('No se pudieron cargar los avisos: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _read(Map<String, dynamic> row) async {
    if (row['read_at'] == null) {
      try {
        await _service.markNotificationRead(row['id'].toString());
        if (mounted) setState(() => row['read_at'] = DateTime.now().toUtc().toIso8601String());
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos'),
        actions: [IconButton(onPressed: _load, tooltip: 'Actualizar', icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('No hay avisos.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final row = _rows[index];
                      final unread = row['read_at'] == null;
                      return Card(
                        color: unread ? const Color(0xFFEAF0FF) : Colors.white,
                        child: ListTile(
                          onTap: () => _read(row),
                          leading: Icon(unread ? Icons.notifications_active : Icons.notifications_none, color: unread ? const Color(0xFF142A5C) : Colors.grey),
                          title: Text(row['title']?.toString() ?? '', style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                          subtitle: Text('${row['body'] ?? ''}\n${_formatDate(row['created_at'])}'),
                          isThreeLine: true,
                          trailing: unread ? const Chip(label: Text('Nuevo')) : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? value?.toString() ?? '' : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
