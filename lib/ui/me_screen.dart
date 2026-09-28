import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'change_password_screen.dart';
import 'devices_screen.dart';
import 'ledger_backup_actions.dart';
import 'messages_screen.dart';
import 'user_manual_screen.dart';

/// 底部 Tab「我的」：资料、消息、账号、数据、主题、帮助。
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = context.watch<ThemeController>();
    final unread = auth.unreadMessages;
    final flags = auth.featureFlags;
    final profile = auth.profile;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(
                      Icons.local_shipping,
                      size: 32,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.username ?? '未登录',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (auth.licensePlate != null &&
                            auth.licensePlate!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.primary),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              auth.licensePlate!,
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                        if (profile != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _membershipLine(profile),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            children: [
              if (flags.messages)
                _NavTile(
                  icon: Icons.mail_outline,
                  title: '消息中心',
                  trailing: unread > 0
                      ? Badge(
                          label: Text('$unread'),
                          child: const Icon(Icons.chevron_right),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const MessagesScreen(),
                      ),
                    ).then((_) {
                      if (context.mounted) {
                        context.read<AuthController>().refreshInbox();
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '账号',
            children: [
              _NavTile(
                icon: Icons.lock_outline,
                title: '修改密码',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  );
                },
              ),
              _NavTile(
                icon: Icons.devices,
                title: '登录设备',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DevicesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '数据',
            children: [
              if (flags.backupImport) ...[
                _NavTile(
                  icon: Icons.upload_file_outlined,
                  title: '导出备份',
                  onTap: () => LedgerBackupActions.export(context),
                ),
                _NavTile(
                  icon: Icons.download_outlined,
                  title: '导入账本',
                  onTap: () => LedgerBackupActions.import(context),
                ),
              ],
              _NavTile(
                icon: Icons.sync,
                title: '同步与冲突',
                subtitle: '智能同步、上传/拉取',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '外观',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto, size: 18),
                      label: Text('系统'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {theme.mode},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) {
                      context.read<ThemeController>().setMode(set.first);
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '深色为 OLED 纯黑，更省电、夜间更清晰',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '帮助',
            children: [
              _NavTile(
                icon: Icons.menu_book_outlined,
                title: '使用手册',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const UserManualScreen(),
                    ),
                  );
                },
              ),
              _NavTile(
                icon: Icons.info_outline,
                title: '关于',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          if (!kReleaseMode) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '调试',
              children: [
                _NavTile(
                  icon: Icons.dns_outlined,
                  title: '服务器与连接（仅调试）',
                  onTap: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('退出登录'),
                  content: const Text('确定退出当前账号？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('退出'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<AuthController>().logout();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }

  static String _membershipLine(UserProfile profile) {
    final planZh = switch (profile.plan) {
      'trial' => '试用中',
      'paid' => '正式版',
      _ => profile.plan.isNotEmpty ? profile.plan : profile.status,
    };
    final days = profile.daysLeft;
    if (days != null) {
      return '$planZh · 剩余 $days 天';
    }
    return planZh;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
