import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _usersProvider = FutureProvider<List<AdminUser>>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.listUsers();
});

class AdminUsersPage extends ConsumerWidget {
  const AdminUsersPage({super.key});

  Future<void> _editUser(BuildContext context, WidgetRef ref,
      {AdminUser? existing}) async {
    final repo = await ref.read(adminRepositoryProvider.future);
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserEditDialog(existing: existing, repo: repo),
    );
    if (saved == true) ref.invalidate(_usersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_usersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_usersProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('新建用户'),
        onPressed: () => _editUser(context, ref),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', textAlign: TextAlign.center),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('暂无用户'));
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(u.username.isEmpty
                      ? '?'
                      : u.username.substring(0, 1).toUpperCase()),
                ),
                title: Text(u.username),
                subtitle: Text(u.isAdmin ? '管理员' : '普通用户'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑',
                  onPressed: () => _editUser(context, ref, existing: u),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserEditDialog extends StatefulWidget {
  final AdminUser? existing;
  final dynamic repo;

  const _UserEditDialog({required this.existing, required this.repo});

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _username;
  final _password = TextEditingController();
  late String _role;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.existing?.username ?? '');
    _role = widget.existing?.role ?? 'user';
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.saveUser(
        username: _username.text.trim(),
        password: _password.text,
        role: _role,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑用户' : '新建用户'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _username,
                enabled: !isEdit,
                decoration: const InputDecoration(labelText: '用户名'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '必填' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: isEdit ? '新密码（留空则不修改）' : '密码',
                ),
                validator: (v) {
                  if (isEdit) return null;
                  if (v == null || v.length < 6) return '至少 6 个字符';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: '角色'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('普通用户')),
                  DropdownMenuItem(value: 'admin', child: Text('管理员')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'user'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
