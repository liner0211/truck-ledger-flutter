import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../state/auth_controller.dart';
import '../state/ledger_controller.dart';

/// 登录后：控制面检查 → 权益 → 进入子树。
class ControlGate extends StatefulWidget {
  const ControlGate({super.key, required this.child});

  final Widget child;

  @override
  State<ControlGate> createState() => _ControlGateState();
}

class _ControlGateState extends State<ControlGate> with WidgetsBindingObserver {
  bool _checking = true;
  String? _blockTitle;
  String? _blockBody;
  bool _blocked = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runCheck(silent: true);
    }
  }

  Future<void> _runCheck({bool silent = false}) async {
    final auth = context.read<AuthController>();
    if (!auth.isLoggedIn) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _checking = true;
        _blocked = false;
        _blockTitle = null;
        _blockBody = null;
      });
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final result = await auth.runControlCheck(info.version);
      if (!mounted) return;
      if (result == null) {
        setState(() => _checking = false);
        return;
      }
      if (!result.allowed) {
        final reason = result.reason ?? 'BLOCKED';
        String title = '暂时无法使用';
        String body = result.maintenanceMessage;
        if (reason == 'MAINTENANCE' || reason == 'DISABLED') {
          title = reason == 'MAINTENANCE' ? '系统维护中' : '服务已停用';
          if (body.isEmpty) body = '请稍后再试，或联系管理员。';
        } else if (reason == 'UPDATE_REQUIRED') {
          title = '需要更新应用';
          body =
              '当前版本过低。最低要求 ${result.minVersion}，最新 ${result.latestVersion}。\n请更新后再打开。';
        } else if (reason == 'DEVICE_REVOKED') {
          title = '本设备已被吊销';
          body = '请联系管理员，或在其他设备登录。';
          await auth.logout();
        } else if (reason == 'SUSPENDED' || reason == 'REVOKED' || reason == 'EXPIRED') {
          title = '账号不可用';
          body = reason == 'EXPIRED' ? '试用或订阅已到期，请联系管理员开通。' : '账号状态：$reason';
          if (reason != 'EXPIRED') await auth.logout();
        }
        setState(() {
          _checking = false;
          _blocked = true;
          _blockTitle = title;
          _blockBody = body;
        });
        return;
      }

      final profile = result.account ?? auth.profile;
      String? banner;
      if (result.announcement.trim().isNotEmpty) {
        banner = result.announcement.trim();
      } else if (profile != null && profile.isTrial && profile.daysLeft != null) {
        banner = '试用剩余 ${profile.daysLeft} 天';
        if (!profile.writeAllowed) {
          banner = '试用已到期，当前为只读模式';
        }
      } else if (profile != null && !profile.writeAllowed) {
        banner = '当前账号为只读，无法修改账本';
      }

      // 启动后自动对账一次
      try {
        await context.read<LedgerController>().syncWithCloud();
      } catch (_) {}

      try {
        await auth.bootstrapPushAndInbox();
        if (auth.unreadMessages > 0) {
          banner = banner == null || banner.isEmpty
              ? '您有 ${auth.unreadMessages} 条未读消息'
              : banner;
        }
      } catch (_) {}

      setState(() {
        _checking = false;
        _blocked = false;
        _banner = banner;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        setState(() => _checking = false);
        return;
      }
      final grace = await auth.isWithinOfflineGrace();
      if (grace) {
        setState(() {
          _checking = false;
          _blocked = false;
          _banner = '离线模式（宽限期内）';
        });
      } else {
        setState(() {
          _checking = false;
          _blocked = true;
          _blockTitle = '无法连接服务器';
          _blockBody = e.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final grace = await auth.isWithinOfflineGrace();
      setState(() {
        _checking = false;
        if (grace) {
          _blocked = false;
          _banner = '离线模式（宽限期内）';
        } else {
          _blocked = true;
          _blockTitle = '控制检查失败';
          _blockBody = '$e';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_blocked) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  _blockTitle ?? '不可用',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(_blockBody ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => _runCheck(),
                  child: const Text('重试'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await context.read<AuthController>().logout();
                  },
                  child: const Text('退出登录'),
                ),
                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '设备平台：${Platform.operatingSystem}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_banner != null && _banner!.isNotEmpty)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_banner!, style: const TextStyle(fontSize: 13))),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _banner = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
