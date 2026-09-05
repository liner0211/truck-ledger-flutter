import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../services/sync_service.dart';
import '../state/auth_controller.dart';
import '../state/ledger_controller.dart';
import 'devices_screen.dart';
import 'change_password_screen.dart';
import 'messages_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _serverUrl = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _serverUrl.text = context.read<AuthController>().serverUrl;
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final msg = await action();
    if (mounted) {
      setState(() {
        _busy = false;
        _status = msg;
      });
    }
  }

  Future<void> _saveServerUrl() async {
    await context.read<AuthController>().setServerUrl(_serverUrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器地址已保存')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final auth = context.read<AuthController>();
      await auth.setServerUrl(_serverUrl.text);
      await auth.api.checkHealth();
      if (mounted) setState(() => _status = '服务器连接正常');
    } on ApiException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } catch (e) {
      if (mounted) setState(() => _status = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _syncLabel(SyncStatus s) {
    switch (s) {
      case SyncStatus.idle:
        return '空闲';
      case SyncStatus.synced:
        return '已同步';
      case SyncStatus.dirty:
        return '待上传';
      case SyncStatus.pending:
        return '同步中';
      case SyncStatus.conflict:
        return '冲突';
      case SyncStatus.error:
        return '失败';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final ledger = context.watch<LedgerController>();
    final profile = auth.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('账号与同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前用户', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(auth.username ?? '未登录'),
                  if (auth.licensePlate != null && auth.licensePlate!.isNotEmpty)
                    Text('车牌号：${auth.licensePlate}'),
                  if (auth.userId != null)
                    Text('用户 ID：${auth.userId}', style: Theme.of(context).textTheme.bodySmall),
                  if (profile != null) ...[
                    const SizedBox(height: 8),
                    Text('状态：${profile.status} · 套餐：${profile.plan}'),
                    if (profile.daysLeft != null) Text('剩余天数：${profile.daysLeft}'),
                    Text(profile.writeAllowed ? '写入：允许' : '写入：只读'),
                  ],
                  const SizedBox(height: 4),
                  Text('本机 revision：${auth.localRevision}',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('同步状态：${_syncLabel(ledger.syncStatus)}',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (ledger.syncStatus == SyncStatus.pending) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: ledger.syncProgress,
                    ),
                    if (ledger.syncProgressMessage.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ledger.syncProgress == null
                            ? ledger.syncProgressMessage
                            : '${ledger.syncProgressMessage} · ${((ledger.syncProgress ?? 0) * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                  if (ledger.syncError != null)
                    Text(ledger.syncError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline),
            title: const Text('消息中心'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const MessagesScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices),
            title: const Text('登录设备'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const DevicesScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('修改密码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()),
              );
            },
          ),
          if (!kReleaseMode) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _serverUrl,
              decoration: const InputDecoration(
                labelText: '服务器地址（仅调试）',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _saveServerUrl,
                  child: const Text('保存地址'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _testConnection,
                  child: const Text('测试连接'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _status = null;
                      });
                      try {
                        await auth.api.checkHealth();
                        if (mounted) setState(() => _status = '云服务连接正常');
                      } on ApiException catch (e) {
                        if (mounted) setState(() => _status = e.message);
                      } catch (e) {
                        if (mounted) {
                          setState(() => _status = '连接失败，请检查网络后重试');
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('测试云服务连接'),
            ),
          ],
          const SizedBox(height: 20),
          Text('数据同步', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '修改账本后会自动上传（带版本锁）。冲突时请手动选择保留本机或云端。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (ledger.syncStatus == SyncStatus.conflict) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('检测到版本冲突', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(ledger.resolveConflictKeepLocal),
                      child: const Text('保留本机并强制上传'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(ledger.resolveConflictTakeRemote),
                      child: const Text('采用云端覆盖本机'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_busy || ledger.syncStatus == SyncStatus.pending) ...[
            LinearProgressIndicator(
              value: ledger.syncStatus == SyncStatus.pending ? ledger.syncProgress : null,
            ),
            const SizedBox(height: 8),
            if (ledger.syncStatus == SyncStatus.pending &&
                ledger.syncProgressMessage.isNotEmpty)
              Text(
                ledger.syncProgressMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (ledger.syncStatus == SyncStatus.pending &&
                ledger.syncProgressMessage.isNotEmpty)
              const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(ledger.syncWithCloud),
            icon: const Icon(Icons.sync),
            label: const Text('智能同步'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(ledger.pushToCloud),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('上传到云端'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('从云端拉取'),
                        content: const Text(
                          '将用云端账本覆盖本机全部圈次（附件会尽量下载）。确定继续？',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('拉取'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && mounted) {
                      await _run(ledger.pullFromCloud);
                    }
                  },
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('从云端拉取（覆盖本机）'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!),
          ],
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy
                ? null
                : () async {
                    await auth.logout();
                    if (context.mounted) Navigator.pop(context);
                  },
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}
