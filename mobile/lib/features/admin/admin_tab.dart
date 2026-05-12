import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminTab extends StatelessWidget {
  const AdminTab({super.key});

  static const _entries = <_Entry>[
    _Entry(
      icon: Icons.dashboard_outlined,
      title: '数据概览',
      subtitle: '番剧 / 剧集 / 文件 / 用户统计',
      route: '/admin/overview',
    ),
    _Entry(
      icon: Icons.monitor_heart_outlined,
      title: '系统监控',
      subtitle: '运行时间 / 内存 / 服务就绪',
      route: '/admin/monitor',
    ),
    _Entry(
      icon: Icons.fact_check_outlined,
      title: '下载申请审批',
      subtitle: '通过或拒绝用户的下载请求',
      route: '/admin/download-requests',
    ),
    _Entry(
      icon: Icons.article_outlined,
      title: '日志查看',
      subtitle: '最近的系统日志条目',
      route: '/admin/logs',
    ),
    _Entry(
      icon: Icons.people_outline,
      title: '用户管理',
      subtitle: '新建用户 / 改密码 / 调整角色',
      route: '/admin/users',
    ),
    _Entry(
      icon: Icons.confirmation_number_outlined,
      title: '邀请码',
      subtitle: '生成 / 删除 / 复制邀请码',
      route: '/admin/invite-codes',
    ),
    _Entry(
      icon: Icons.tv_outlined,
      title: '番剧管理',
      subtitle: '查看 / 批量删除已索引番剧',
      route: '/admin/anime',
    ),
    _Entry(
      icon: Icons.storage_outlined,
      title: '储存桶配置',
      subtitle: '存储类型 / PikPak / 115 / Aria2 / 本地路径',
      route: '/admin/storage',
    ),
    _Entry(
      icon: Icons.settings_outlined,
      title: '系统设置',
      subtitle: '登录策略 / Mikan 账号 / 下载上限',
      route: '/admin/settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理'),
        automaticallyImplyLeading: false,
      ),
      body: ListView.separated(
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = _entries[i];
          return ListTile(
            leading: Icon(e.icon),
            title: Text(e.title),
            subtitle: Text(e.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(e.route),
          );
        },
      ),
    );
  }
}

class _Entry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}
