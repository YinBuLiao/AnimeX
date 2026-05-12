import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';
import 'package:animex_mobile/data/repositories/system_repository.dart';

class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key});

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  final _urlController = TextEditingController();
  bool _allowSelfSigned = false;
  bool _busy = false;
  String? _error;
  HealthInfo? _lastHealth;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _error = null;
      _lastHealth = null;
      _busy = true;
    });
    try {
      final config = ServerConfig.normalize(
        _urlController.text,
        allowSelfSigned: _allowSelfSigned,
      );
      final builder = ref.read(dioBuilderProvider);
      final dio = builder(
        config: config,
        sessionStore: ref.read(sessionStoreProvider),
      );
      final health = await SystemRepository(dio).health();
      await ref.read(serverConfigStoreProvider).save(config);
      ref.invalidate(serverConfigProvider);
      if (!mounted) return;
      setState(() {
        _lastHealth = health;
      });
    } on FormatException catch (e) {
      setState(() => _error = '${e.message}（请填写 http:// 或 https:// 开头的地址）');
    } on ApiException catch (e) {
      setState(() => _error = '连接失败: ${e.message}');
    } catch (e) {
      setState(() => _error = '连接失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _proceedToLogin() => context.go('/login');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AnimeX')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('服务器地址',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://anime.example.com:8080',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _allowSelfSigned,
                    onChanged: (v) =>
                        setState(() => _allowSelfSigned = v ?? false),
                  ),
                  const Expanded(child: Text('忽略 HTTPS 证书错误')),
                ],
              ),
              if (_allowSelfSigned)
                const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: 8),
                  child: Text(
                    '仅在你完全信任此服务器（如自宅自签证书）时启用。',
                    style:
                        TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _testConnection,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
              const SizedBox(height: 12),
              if (_lastHealth != null) ...[
                Text('连接成功：版本 ${_lastHealth!.version}'),
                const SizedBox(height: 8),
                if (!_lastHealth!.installed)
                  const Text(
                    '⚠️ 服务器尚未完成安装向导，请先在 Web 端完成安装。',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed:
                      _lastHealth!.installed ? _proceedToLogin : null,
                  child: const Text('下一步：登录'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
