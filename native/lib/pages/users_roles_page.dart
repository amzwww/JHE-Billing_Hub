import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';

class UsersRolesPage extends StatefulWidget {
  const UsersRolesPage({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<UsersRolesPage> createState() => _UsersRolesPageState();
}

class _UsersRolesPageState extends State<UsersRolesPage> {
  final _service = BillsService();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _service.managedUsers();
      if (mounted) setState(() => _users = users);
    } catch (error) {
      if (mounted) _message('No se pudieron cargar los usuarios: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final values = await _formDialog();
    if (values == null) return;
    try {
      await _service.createManagedUser(
        nickname: values.nickname,
        email: values.email,
        password: values.password!,
        role: values.role,
      );
      _load();
    } catch (error) {
      if (mounted) _message('No se pudo crear el usuario: $error');
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final values = await _formDialog(row: row);
    if (values == null) return;
    try {
      await _service.updateManagedUser(
        userId: row['id'].toString(),
        nickname: values.nickname,
        email: values.email,
        password: values.password,
        role: values.role,
      );
      _load();
    } catch (error) {
      if (mounted) _message('No se pudo actualizar el usuario: $error');
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
          '¿Eliminar ${row['email']}? Esta acción también elimina su rol.',
        ),
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
      await _service.deleteManagedUser(row['id'].toString());
      _load();
    } catch (error) {
      if (mounted) _message('No se pudo eliminar el usuario: $error');
    }
  }

  Future<_UserFormValues?> _formDialog({Map<String, dynamic>? row}) async {
    final nickname = TextEditingController(
      text: row?['nickname']?.toString() ?? '',
    );
    final email = TextEditingController(text: row?['email']?.toString() ?? '');
    final password = TextEditingController();
    var role = row?['role']?.toString() == 'admin' ? 'admin' : 'gestion';
    final values = await showDialog<_UserFormValues>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(row == null ? 'Nuevo usuario' : 'Editar usuario'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nickname,
                  decoration: const InputDecoration(labelText: 'Apodo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: row == null
                        ? 'Contraseña'
                        : 'Nueva contraseña (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrador'),
                    ),
                    DropdownMenuItem(value: 'gestion', child: Text('Gestión')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? 'gestion'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nickname.text.trim().isEmpty ||
                    email.text.trim().isEmpty ||
                    (row == null && password.text.length < 6))
                  return;
                Navigator.pop(
                  dialogContext,
                  _UserFormValues(
                    nickname.text.trim(),
                    email.text.trim(),
                    password.text.isEmpty ? null : password.text,
                    role,
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    nickname.dispose();
    email.dispose();
    password.dispose();
    return values;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
        title: const Text('Usuarios y roles'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20, left: 8),
            child: FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.person_add),
              label: const Text('Nuevo usuario'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? const Center(child: Text('No hay usuarios.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Apodo')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Rol')),
                  DataColumn(label: Text('Alta')),
                  DataColumn(label: Text('Último acceso')),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: [
                  for (final row in _users)
                    DataRow(
                      cells: [
                        DataCell(Text(row['nickname']?.toString() ?? '')),
                        DataCell(Text(row['email']?.toString() ?? '')),
                        DataCell(
                          _roleChip(row['role']?.toString() ?? 'gestion'),
                        ),
                        DataCell(Text(_date(row['created_at']))),
                        DataCell(Text(_date(row['last_sign_in_at']))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _edit(row),
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: () => _delete(row),
                                tooltip: 'Eliminar',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _roleChip(String role) => Chip(
    label: Text(role == 'admin' ? 'Administrador' : 'Gestión'),
    avatar: Icon(
      role == 'admin'
          ? Icons.admin_panel_settings_outlined
          : Icons.manage_accounts_outlined,
      size: 17,
    ),
  );

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? '—'
        : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _UserFormValues {
  const _UserFormValues(this.nickname, this.email, this.password, this.role);
  final String nickname;
  final String email;
  final String? password;
  final String role;
}
