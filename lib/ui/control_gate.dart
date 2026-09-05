import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/app_updater.dart';
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
  String? _updateUrl;
  bool _updating = false;
  double _updateProgress = 0;

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
        _updateUrl = null;
      });
    }
    try {
      final info = await PackageInfo.fromPlatform();
      // 带构建号，便于控制面识别「同营销版本的新 CI 包」
      final appVersion = '${info.version}+${info.buildNumber}';
      final result = await auth.runControlCheck(appVersion);
      if (!mounted) return;
      if (result == null) {
        setState(() => _checking = false);
        return;
      }
      if (!result.allowed) {
        final reason = result.reason ?? 'BLOCKED';
        String title = '暂时无法使用';
        String body = result.maintenanceMessage;
        String? updateUrl;
        if (reason == 'MAINTENANCE' || reason == 'DISABLED') {
          title = reason == 'MAINTENANCE' ? '系统维护中' : '服务已停用';
          if (body.isEmpty) body = '请稍后再试，或联系管理员。';
        } else if (reason == 'VERSION_TOO_LOW' || reason == 'UPDATE_REQUIRED') {
          title = '需要更新应用';
          body =
              '当前版本过低。最低要求 ${result.minVersion}，最新 ${result.latestVersion}。\n请更新后再打开。';
          updateUrl = result.update.downloadUrl;
          if (result.update.releaseNotes.isNotEmpty) {
            body = '$body\n\n${result.update.releaseNotes}';
          }
        } else if (reason == 'FORCE_UPDATE') {
          title = '请更新到最新版';
          body =
              '管理员要求更新到 ${result.latestVersion}（当前 $appVersion）。';
          updateUrl = result.update.downloadUrl;
          if (result.update.releaseNotes.isNotEmpty) {
            body = '$body\n\n${result.update.releaseNotes}';
          }
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
          _updateUrl = updateUrl;
        });
        return;
      }

      final profile = result.account ?? auth.profile;
      String? banner;
      if (result.update.available && result.update.downloadUrl.isNotEmpty) {
        banner = '发现新版本 ${result.latestVersion}，可在关于页更新';
      } else if (result.announcement.trim().isNotEmpty) {
        banner = result.announcement.trim();
      } else if (profile != null && profile.isTrial && profile.daysLeft != null) {
        banner = '试用剩余 ${profile.daysLeft} 天';
        if (!profile.writeAllowed) {
          banner = '试用已到期，当前为只读模式';
        }
      } else if (profile != null && !profile.writeAllowed) {
        banner = '当前账号为只读，无法修改账本';
      }

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
        _updateUrl = result.update.available ? result.update.downloadUrl : null;
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

  Future<void> _doUpdate() async {
    final url = _updateUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未配置下载地址，请联系管理员')),
      );
      return;
    }
    setState(() {
      _updating = true;
      _updateProgress = 0;
    });
    try {
      await AppUpdater.openOrInstall(
        url,
        onProgress: (p) {
          if (mounted) setState(() => _updateProgress = p);
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
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
      final canUpdate = _updateUrl != null && _updateUrl!.isNotEmpty;
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.system_update, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  _blockTitle ?? '不可用',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(_blockBody ?? '', textAlign: TextAlign.center),
                if (_updating) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _updateProgress > 0 && _updateProgress < 1
                        ? _updateProgress
                        : (_updateProgress >= 1 ? 1 : null),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _updateProgress <= 0
                        ? '准备下载…'
                        : _updateProgress >= 1
                            ? '下载完成，正在打开安装包…'
                            : '下载中… ${(_updateProgress * 100).toStringAsFixed(0)}%',
                  ),
                ],
                const SizedBox(height: 24),
                if (canUpdate)
                  FilledButton(
                    onPressed: _updating ? null : _doUpdate,
                    child: const Text('立即更新'),
                  ),
                if (canUpdate) const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _updating ? null : () => _runCheck(),
                  child: const Text('重试'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _updating
                      ? null
                      : () async {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_banner!, style: const TextStyle(fontSize: 13))),
                        if (_updateUrl != null && _updateUrl!.isNotEmpty)
                          TextButton(
                            onPressed: _updating ? null : _doUpdate,
                            child: Text(_updating ? '下载中' : '更新'),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _updating ? null : () => setState(() => _banner = null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    if (_updating) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _updateProgress > 0 && _updateProgress < 1
                            ? _updateProgress
                            : (_updateProgress >= 1 ? 1 : null),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _updateProgress <= 0
                            ? '准备下载…'
                            : _updateProgress >= 1
                                ? '下载完成…'
                                : '下载 ${(_updateProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
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
