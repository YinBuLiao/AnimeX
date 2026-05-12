import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.login(_userController.text.trim(), _passController.text);
      ref.invalidate(currentSessionProvider);
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(serverConfigProvider);
    final serverLabel = config.maybeWhen(
      data: (c) => c.baseUrl,
      orElse: () => '',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: [
          if (serverLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(serverLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _userController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  await ref.read(serverConfigStoreProvider).clear();
                  ref.invalidate(serverConfigProvider);
                  if (mounted) router.go('/setup');
                },
                child: const Text('更换服务器'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
