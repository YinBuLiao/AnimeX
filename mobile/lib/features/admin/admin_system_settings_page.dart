import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';

/// Single-page form bound to /api/admin/config. The same shape backs both
/// "系统设置" and "储存桶配置" entries — the page groups fields into
/// sections so either navigation target lands on something useful.
class AdminSystemSettingsPage extends ConsumerStatefulWidget {
  /// When non-null, the page scrolls / opens with the matching section
  /// expanded. Values: 'system' | 'mikan' | 'storage' | 'pikpak'.
  final String? focusSection;

  const AdminSystemSettingsPage({super.key, this.focusSection});

  @override
  ConsumerState<AdminSystemSettingsPage> createState() =>
      _AdminSystemSettingsPageState();
}

class _AdminSystemSettingsPageState
    extends ConsumerState<AdminSystemSettingsPage> {
  Map<String, dynamic>? _config;
  String? _loadError;
  bool _busy = false;
  String? _saveMsg;

  // System
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _requireLogin = false;
  bool _enableRegistration = false;
  bool _requireInvite = false;
  final _dailyLimit = TextEditingController();

  // Mikan
  final _mikanUsername = TextEditingController();
  final _mikanPassword = TextEditingController();

  // PikPak
  String _pikpakAuthMode = 'password';
  final _pikpakAccess = TextEditingController();
  final _pikpakRefresh = TextEditingController();
  final _pikpakEncoded = TextEditingController();

  // Storage
  String _storageProvider = 'pikpak';
  final _drive115Cookie = TextEditingController();
  final _drive115Root = TextEditingController();
  final _aria2Url = TextEditingController();
  final _aria2Secret = TextEditingController();
  final _localPath = TextEditingController();
  final _nasPath = TextEditingController();
  final _downloadPath = TextEditingController();
  final _rss = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _username,
      _password,
      _dailyLimit,
      _mikanUsername,
      _mikanPassword,
      _pikpakAccess,
      _pikpakRefresh,
      _pikpakEncoded,
      _drive115Cookie,
      _drive115Root,
      _aria2Url,
      _aria2Secret,
      _localPath,
      _nasPath,
      _downloadPath,
      _rss,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final repo = await ref.read(adminRepositoryProvider.future);
      final cfg = await repo.getSystemConfig();
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _hydrate(cfg);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '$e');
    }
  }

  void _hydrate(Map<String, dynamic> cfg) {
    String s(String k) => (cfg[k] ?? '').toString();
    bool b(String k) => cfg[k] == true;
    _username.text = s('username');
    _password.text = s('password');
    _requireLogin = b('require_login');
    _enableRegistration = b('enable_registration');
    _requireInvite = b('require_invite');
    _dailyLimit.text = (cfg['user_daily_download_limit'] ?? 0).toString();
    _mikanUsername.text = s('mikan_username');
    _mikanPassword.text = s('mikan_password');
    _pikpakAuthMode = s('pikpak_auth_mode').isEmpty
        ? 'password'
        : s('pikpak_auth_mode');
    _pikpakAccess.text = s('pikpak_access_token');
    _pikpakRefresh.text = s('pikpak_refresh_token');
    _pikpakEncoded.text = s('pikpak_encoded_token');
    _storageProvider =
        s('storage_provider').isEmpty ? 'pikpak' : s('storage_provider');
    _drive115Cookie.text = s('drive115_cookie');
    _drive115Root.text = s('drive115_root_cid');
    _aria2Url.text = s('aria2_rpc_url');
    _aria2Secret.text = s('aria2_rpc_secret');
    _localPath.text = s('local_storage_path');
    _nasPath.text = s('nas_storage_path');
    _downloadPath.text = s('path');
    _rss.text = s('rss');
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _saveMsg = null;
    });
    final patch = <String, dynamic>{
      'username': _username.text,
      'password': _password.text,
      'require_login': _requireLogin,
      'enable_registration': _enableRegistration,
      'require_invite': _requireInvite,
      'user_daily_download_limit':
          int.tryParse(_dailyLimit.text.trim()) ?? 0,
      'mikan_username': _mikanUsername.text,
      'mikan_password': _mikanPassword.text,
      'pikpak_auth_mode': _pikpakAuthMode,
      'pikpak_access_token': _pikpakAccess.text,
      'pikpak_refresh_token': _pikpakRefresh.text,
      'pikpak_encoded_token': _pikpakEncoded.text,
      'storage_provider': _storageProvider,
      'drive115_cookie': _drive115Cookie.text,
      'drive115_root_cid': _drive115Root.text,
      'aria2_rpc_url': _aria2Url.text,
      'aria2_rpc_secret': _aria2Secret.text,
      'local_storage_path': _localPath.text,
      'nas_storage_path': _nasPath.text,
      'path': _downloadPath.text,
      'rss': _rss.text,
    };
    try {
      final repo = await ref.read(adminRepositoryProvider.future);
      final updated = await repo.saveSystemConfig(patch);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _config = updated;
        _hydrate(updated);
        _saveMsg = '保存成功';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveMsg = '保存失败：${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveMsg = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final initiallyExpanded = widget.focusSection;
    return Scaffold(
      appBar: AppBar(
        title: Text(initiallyExpanded == 'storage' ? '储存桶配置' : '系统设置'),
      ),
      floatingActionButton: _config == null
          ? null
          : FloatingActionButton.extended(
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('保存'),
              onPressed: _busy ? null : _save,
            ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : _config == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    if (_saveMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _saveMsg!.startsWith('保存成功')
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                              : Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_saveMsg!),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _section(
                      title: '系统',
                      initiallyExpanded:
                          initiallyExpanded != 'storage',
                      children: [
                        TextField(
                          controller: _username,
                          decoration:
                              const InputDecoration(labelText: '主账号用户名'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          decoration:
                              const InputDecoration(labelText: '主账号密码'),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('需要登录'),
                          value: _requireLogin,
                          onChanged: (v) => setState(() => _requireLogin = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('允许注册'),
                          value: _enableRegistration,
                          onChanged: (v) =>
                              setState(() => _enableRegistration = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('注册需邀请码'),
                          value: _requireInvite,
                          onChanged: (v) =>
                              setState(() => _requireInvite = v),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _dailyLimit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '每日每用户下载上限',
                            helperText: '0 表示不限',
                          ),
                        ),
                      ],
                    ),
                    _section(
                      title: 'Mikan 账号',
                      initiallyExpanded:
                          initiallyExpanded == 'mikan',
                      children: [
                        TextField(
                          controller: _mikanUsername,
                          decoration:
                              const InputDecoration(labelText: '用户名'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _mikanPassword,
                          decoration:
                              const InputDecoration(labelText: '密码'),
                          obscureText: true,
                        ),
                      ],
                    ),
                    _section(
                      title: '存储桶',
                      initiallyExpanded: initiallyExpanded == 'storage',
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _storageProvider,
                          decoration: const InputDecoration(
                              labelText: '存储类型'),
                          items: const [
                            DropdownMenuItem(
                                value: 'pikpak', child: Text('PikPak')),
                            DropdownMenuItem(
                                value: 'drive115', child: Text('115 网盘')),
                            DropdownMenuItem(
                                value: 'local', child: Text('本地磁盘')),
                            DropdownMenuItem(
                                value: 'nas', child: Text('NAS 路径')),
                          ],
                          onChanged: (v) => setState(
                              () => _storageProvider = v ?? 'pikpak'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _downloadPath,
                          decoration: const InputDecoration(
                            labelText: 'PikPak 下载父目录',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _rss,
                          decoration: const InputDecoration(
                            labelText: 'Mikan RSS',
                          ),
                        ),
                        if (_storageProvider == 'drive115') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _drive115Cookie,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: '115 Cookie',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _drive115Root,
                            decoration: const InputDecoration(
                              labelText: '115 根目录 CID',
                            ),
                          ),
                        ],
                        if (_storageProvider == 'local') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _localPath,
                            decoration: const InputDecoration(
                              labelText: '本地存储路径',
                            ),
                          ),
                        ],
                        if (_storageProvider == 'nas') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nasPath,
                            decoration: const InputDecoration(
                              labelText: 'NAS 路径',
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _aria2Url,
                          decoration: const InputDecoration(
                            labelText: 'Aria2 RPC URL',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _aria2Secret,
                          decoration: const InputDecoration(
                            labelText: 'Aria2 Secret',
                          ),
                          obscureText: true,
                        ),
                      ],
                    ),
                    _section(
                      title: 'PikPak 鉴权',
                      initiallyExpanded: initiallyExpanded == 'pikpak',
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _pikpakAuthMode,
                          decoration:
                              const InputDecoration(labelText: '鉴权方式'),
                          items: const [
                            DropdownMenuItem(
                                value: 'password',
                                child: Text('账号密码（系统主账号）')),
                            DropdownMenuItem(
                                value: 'token', child: Text('Token')),
                          ],
                          onChanged: (v) => setState(
                              () => _pikpakAuthMode = v ?? 'password'),
                        ),
                        if (_pikpakAuthMode == 'token') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pikpakEncoded,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Encoded Token',
                              helperText: '优先使用；填了下面两项就不用填这个',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pikpakAccess,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Access Token',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pikpakRefresh,
                            decoration: const InputDecoration(
                              labelText: 'Refresh Token',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: children,
      ),
    );
  }
}
