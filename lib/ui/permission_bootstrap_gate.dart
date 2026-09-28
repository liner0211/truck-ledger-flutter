import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_permission_service.dart';

/// 首次启动：自动弹出系统相册授权；并说明网络权限为何无弹窗。
class PermissionBootstrapGate extends StatefulWidget {
  const PermissionBootstrapGate({super.key, required this.child});

  final Widget child;

  @override
  State<PermissionBootstrapGate> createState() => _PermissionBootstrapGateState();
}

class _PermissionBootstrapGateState extends State<PermissionBootstrapGate> {
  bool _loading = true;
  AppPermissionReport? _report;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    AppPermissionReport report;
    try {
      report = await AppPermissionService.requestAllRuntimePermissions()
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // 权限弹窗卡住时放行，避免永久转圈
      report = AppPermissionReport()..photos = PermissionStatus.granted;
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _retryPhotos() async {
    setState(() => _loading = true);
    AppPermissionReport report;
    try {
      report = await AppPermissionService.requestAllRuntimePermissions()
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      report = AppPermissionReport()..photos = PermissionStatus.denied;
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在申请应用权限…'),
            ],
          ),
        ),
      );
    }

    final report = _report!;
    if (report.photosOk) {
      return widget.child;
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.security, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                '应用权限说明',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 20),
              _section(
                context,
                title: '网络（访问服务器）',
                body: 'Android 与 iOS 访问互联网不需要也不会弹出授权框。\n'
                    'Android 的 INTERNET 权限在安装应用时已自动授予（含 Android 16）。\n'
                    '若无法连接服务器，请在系统设置中确认本应用已允许 WLAN / 移动数据。',
                items: AppPermissionService.installTimeGrants,
              ),
              const SizedBox(height: 16),
              _section(
                context,
                title: '相册（凭证照片）',
                body: '状态：${AppPermissionService.photosStatusLabel(report.photos)}\n'
                    '添加路线/费用凭证时需要此权限，请点击下方按钮授权。',
              ),
              const Spacer(),
              if (report.photosNeedsSettings)
                FilledButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('打开系统设置授权相册'),
                )
              else
                FilledButton.icon(
                  onPressed: _retryPhotos,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('申请相册权限'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _report = AppPermissionReport()..photos = PermissionStatus.granted;
                }),
                child: const Text('暂不授权，先进入应用'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String body,
    List<String> items = const [],
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final i in items)
                Text('· $i', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
