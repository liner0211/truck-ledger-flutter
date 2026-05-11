import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于1')),
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

