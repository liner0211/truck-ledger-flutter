import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();
    final control = auth.lastControl;
    final profile = auth.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '卡车记账',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final style = Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant);
                      if (snap.connectionState != ConnectionState.done) {
                        return Text('版本 …', style: style);
                      }
                      final p = snap.data;
                      if (p == null) return const SizedBox.shrink();
                      return Text(
                        '版本 ${p.version}（构建 ${p.buildNumber}）',
                        style: style,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '软件仅供杨三车队配货运输使用',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (control != null || profile != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('云端通道', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('服务器：${auth.serverUrl}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (control != null) ...[
                      Text('云端最新版本：${control.latestVersion}'),
                      Text('最低版本：${control.minVersion}'),
                      Text('应用状态：${control.appStatus}'),
                      Text('控制版本：${control.controlVersion}'),
                    ],
                    if (profile != null) ...[
                      const SizedBox(height: 6),
                      Text('账号：${profile.status} / ${profile.plan}'),
                      if (profile.daysLeft != null) Text('剩余天数：${profile.daysLeft}'),
                      Text(profile.writeAllowed ? '写入：允许' : '写入：只读'),
                    ],
                    Text('本机 revision：${auth.localRevision}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('作者'),
                  subtitle: Text('张圣康'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.wechat_outlined),
                  title: Text('微信'),
                  subtitle: Text('17631803349'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.email_outlined),
                  title: Text('邮箱'),
                  subtitle: Text('liner0211@gmail.com'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: cs.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '提示：越狱设备安装 deb 时，请避免卸载后重装，以免系统清理应用沙盒导致历史数据丢失。',
                style: TextStyle(height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
