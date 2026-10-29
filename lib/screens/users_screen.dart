import 'package:flutter/material.dart';

import '../api_service.dart';
import '../models.dart';
import '../validators.dart';

/// CRUD de usuarios (solo administradores).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _api = ApiService.instance;
  List<User> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showMessage(Object msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _api.getUsers();
      if (mounted) setState(() => _users = users);
    } catch (e) {
      _showMessage(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([User? user]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(user: user),
    );
    if (saved == true) {
      _showMessage(user == null ? 'Usuario creado' : 'Usuario actualizado');
      _load();
    }
  }

  Future<void> _toggleBlocked(User user) async {
    final block = !user.disabled;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(block ? 'Bloquear usuario' : 'Desbloquear usuario'),
        content: Text(
          block
              ? '¿Bloquear a "${user.username}"? No podrá entrar ni ver sus conversaciones hasta que lo desbloquees.'
              : '¿Desbloquear a "${user.username}"?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(block ? 'Bloquear' : 'Desbloquear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.setUserDisabled(user.id, block);
      _showMessage(block ? 'Usuario bloqueado' : 'Usuario desbloqueado');
      _load();
    } catch (e) {
      _showMessage(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _api.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: _users.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final u = _users[i];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        u.disabled
                            ? Icons.block
                            : u.isAdmin
                            ? Icons.admin_panel_settings
                            : Icons.person,
                      ),
                    ),
                    title: Text(u.name),
                    subtitle: Text(
                      '@${u.username} · ${u.isAdmin ? 'Administrador' : 'Usuario'}'
                      '${u.isGoogle ? ' · Google${u.email != null ? ' (${u.email})' : ''}' : ''}'
                      '${u.disabled ? ' · BLOQUEADO' : ''}',
                    ),
                    onTap: () => _openForm(u),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () => _openForm(u),
                        ),
                        IconButton(
                          icon: Icon(u.disabled ? Icons.lock_open : Icons.block),
                          tooltip: u.disabled ? 'Desbloquear' : 'Bloquear',
                          onPressed: u.id == me.id ? null : () => _toggleBlocked(u),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  final User? user;
  const _UserFormDialog({this.user});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.name);
  late final _username = TextEditingController(text: widget.user?.username);
  final _password = TextEditingController();
  late String _role = widget.user?.role ?? 'user';
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ApiService.instance;
    try {
      if (_isEdit) {
        await api.updateUser(widget.user!.id, name: _name.text.trim(), role: _role);
      } else {
        await api.createUser(
          name: _name.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          role: _role,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Editar usuario' : 'Nuevo usuario'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              // El usuario y la contraseña solo se eligen al crear la cuenta
              TextFormField(
                controller: _username,
                enabled: !_isEdit,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Usuario'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              if (!_isEdit)
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    helperText: 'Mínimo 8 caracteres y un carácter especial',
                  ),
                  // Misma regla que el registro: 8+ caracteres y un carácter especial
                  validator: validatePassword,
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('Usuario')),
                  DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
